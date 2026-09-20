output "application_url" {
  description = "Public URL of the running service."
  value       = "http://${aws_instance.app.public_ip}:8080"
}

output "health_check_url" {
  description = "Health endpoint, the first thing to curl after a deploy."
  value       = "http://${aws_instance.app.public_ip}:8080/actuator/health"
}

output "swagger_url" {
  description = "Interactive API documentation."
  value       = "http://${aws_instance.app.public_ip}:8080/swagger-ui.html"
}

output "ecr_repository_url" {
  description = "Set this as the ECR_REPOSITORY repository variable in GitHub."
  value       = aws_ecr_repository.app.repository_url
}

output "github_actions_role_arn" {
  description = "Set this as the AWS_ROLE_ARN repository variable in GitHub. It is an ARN, not a credential — there is nothing secret about it."
  value       = aws_iam_role.github_actions.arn
}

output "instance_id" {
  description = "Set this as the EC2_INSTANCE_ID repository variable in GitHub."
  value       = aws_instance.app.id
}

output "aws_region" {
  description = "Set this as the AWS_REGION repository variable in GitHub."
  value       = var.aws_region
}

output "vpc_id" {
  description = "VPC identifier."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet identifiers."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet identifiers. No route to an internet gateway."
  value       = aws_subnet.private[*].id
}

output "database_endpoint" {
  description = "RDS endpoint when enable_rds is true, otherwise the container hostname on the instance's docker network."
  value       = var.enable_rds ? aws_db_instance.main[0].endpoint : "postgres (container on the instance's private docker network)"
}

output "session_manager_command" {
  description = "Open a shell on the instance without SSH, without a key pair and without an open inbound port."
  value       = "aws ssm start-session --target ${aws_instance.app.id} --region ${var.aws_region}"
}

output "github_repository_variables" {
  description = "Copy these into GitHub: Settings > Secrets and variables > Actions > Variables."
  value = {
    AWS_REGION      = var.aws_region
    AWS_ROLE_ARN    = aws_iam_role.github_actions.arn
    ECR_REPOSITORY  = aws_ecr_repository.app.repository_url
    EC2_INSTANCE_ID = aws_instance.app.id
  }
}
