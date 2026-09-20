# ---------------------------------------------------------------------------
# Identity
#
# Two identities, each with only the permissions it needs:
#
#   1. The EC2 instance role   - pull images, read its own secrets, be managed
#                                by Systems Manager. No write access anywhere.
#   2. The GitHub Actions role - push images and trigger one deployment
#                                command. Assumed through OIDC, so there is no
#                                AWS access key stored in GitHub at all.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  ssm_parameter_prefix = "/${var.project_name}"
}

# ===========================================================================
# EC2 instance role
# ===========================================================================

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${local.name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "Role assumed by the application instance"
}

# Lets Systems Manager manage the instance. This is what replaces SSH: Session
# Manager and Run Command both work through an outbound agent connection, so
# port 22 can stay closed and there is no key pair to lose.
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Pull-only access to ECR. The instance can never push an image.
resource "aws_iam_role_policy_attachment" "ec2_ecr_read" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Read only this project's own secrets, and decrypt only with the SSM key.
data "aws_iam_policy_document" "ec2_read_secrets" {
  statement {
    sid    = "ReadOwnParameters"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = [
      "arn:${local.partition}:ssm:${var.aws_region}:${local.account_id}:parameter${local.ssm_parameter_prefix}/*",
    ]
  }

  statement {
    sid       = "DecryptSecureStrings"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_alias.ssm.target_key_arn]
  }
}

resource "aws_iam_role_policy" "ec2_read_secrets" {
  name   = "${local.name}-read-secrets"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_read_secrets.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name}-instance-profile"
  role = aws_iam_role.ec2.name
}

# ===========================================================================
# GitHub Actions role, assumed via OIDC
# ===========================================================================

# Fetching the certificate rather than hardcoding a thumbprint means the
# configuration keeps working when GitHub rotates its signing certificate.
data "tls_certificate" "github" {
  count = var.create_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github[0].certificates[0].sha1_fingerprint]

  tags = { Name = "${local.name}-github-oidc" }
}

data "aws_iam_openid_connect_provider" "existing" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.existing[0].arn

  # Only these exact refs of this exact repository may assume the role.
  github_allowed_subs = [
    for ref in var.github_allowed_refs : "repo:${var.github_repository}:ref:${ref}"
  ]
}

data "aws_iam_policy_document" "github_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }

    # Without this audience check the role would trust any GitHub workflow
    # anywhere. With it plus the subject check below, only this repository on
    # the listed refs can assume it.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_allowed_subs
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = "${local.name}-github-actions"
  assume_role_policy   = data.aws_iam_policy_document.github_assume_role.json
  max_session_duration = 3600
  description          = "Assumed by GitHub Actions through OIDC. No long-lived credentials exist for this role."
}

data "aws_iam_policy_document" "github_actions" {
  # GetAuthorizationToken cannot be scoped to a repository; AWS only accepts
  # "*" for it. Every other ECR action below is scoped to this one repository.
  statement {
    sid       = "EcrLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPushToThisRepositoryOnly"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  # The pipeline may run one shell command on one instance. It cannot start,
  # stop, reconfigure or replace it.
  statement {
    sid     = "RunDeployCommandOnThisInstanceOnly"
    effect  = "Allow"
    actions = ["ssm:SendCommand"]
    resources = [
      aws_instance.app.arn,
      "arn:${local.partition}:ssm:${var.aws_region}::document/AWS-RunShellScript",
    ]
  }

  statement {
    sid    = "ReadCommandResults"
    effect = "Allow"
    actions = [
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
      "ssm:DescribeInstanceInformation",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ResolveInstanceAddress"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${local.name}-deploy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions.json
}
