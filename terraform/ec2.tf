# ---------------------------------------------------------------------------
# Application instance
# ---------------------------------------------------------------------------

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "app" {
  ami           = data.aws_ami.al2023.id
  instance_type = var.instance_type

  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.ec2.name

  # No key_name. Access is through SSM Session Manager, so there is no private
  # key that can be lost, committed or shared.

  metadata_options {
    http_endpoint = "enabled"
    # IMDSv2 only. IMDSv1's unauthenticated request is what turns a server-side
    # request forgery bug into leaked instance credentials.
    http_tokens = "required"
    # 2 hops so a process inside a container can still reach the metadata service.
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    aws_region         = var.aws_region
    ssm_prefix         = local.ssm_parameter_prefix
    project_name       = var.project_name
    db_name            = var.db_name
    db_username        = var.db_username
    ecr_repository_url = aws_ecr_repository.app.repository_url
  })

  # Changing the bootstrap script should not silently replace a running
  # instance; re-run it deliberately instead.
  user_data_replace_on_change = false

  # user_data reads these at first boot, so they must exist before it runs.
  depends_on = [
    aws_ssm_parameter.db_password,
    aws_ssm_parameter.db_name,
    aws_ssm_parameter.db_username,
    aws_iam_role_policy.ec2_read_secrets,
    aws_iam_role_policy_attachment.ec2_ssm,
  ]

  tags = { Name = "${local.name}-app" }
}
