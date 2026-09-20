# ---------------------------------------------------------------------------
# Secrets
#
# Nothing sensitive is written into user_data, into the AMI, or into the
# image. The instance reads what it needs from Parameter Store at container
# start, using the role above, and the values are generated here so no human
# ever picks or copies them.
# ---------------------------------------------------------------------------

resource "random_password" "db" {
  length = 32
  # Alphanumeric only: avoids characters that would need escaping inside a
  # JDBC URL or a shell command.
  special = false
}

resource "random_password" "jwt" {
  # HMAC-SHA256 signing keys must be at least 32 bytes; 64 gives headroom.
  length  = 64
  special = false
}

resource "aws_ssm_parameter" "db_password" {
  name        = "${local.ssm_parameter_prefix}/db/password"
  description = "PostgreSQL password for ${var.project_name}"
  type        = "SecureString"
  value       = random_password.db.result
}

resource "aws_ssm_parameter" "jwt_secret" {
  name        = "${local.ssm_parameter_prefix}/jwt/secret"
  description = "JWT signing key for ${var.project_name}"
  type        = "SecureString"
  value       = random_password.jwt.result
}

resource "aws_ssm_parameter" "db_name" {
  name  = "${local.ssm_parameter_prefix}/db/name"
  type  = "String"
  value = var.db_name
}

resource "aws_ssm_parameter" "db_username" {
  name  = "${local.ssm_parameter_prefix}/db/username"
  type  = "String"
  value = var.db_username
}

# Where the application should look for PostgreSQL: the RDS endpoint when RDS
# is enabled, otherwise the sibling container on the instance's docker network.
resource "aws_ssm_parameter" "db_host" {
  name  = "${local.ssm_parameter_prefix}/db/host"
  type  = "String"
  value = var.enable_rds ? aws_db_instance.main[0].address : "postgres"
}

resource "aws_ssm_parameter" "ecr_repository_url" {
  name  = "${local.ssm_parameter_prefix}/ecr/repository-url"
  type  = "String"
  value = aws_ecr_repository.app.repository_url
}
