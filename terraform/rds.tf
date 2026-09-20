# ---------------------------------------------------------------------------
# Managed PostgreSQL (optional; see enable_rds in variables.tf)
#
# Disabled by default on cost grounds. When enabled, the database lands in the
# private subnets, is not publicly accessible, and is reachable only from the
# application security group.
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  count = var.enable_rds ? 1 : 0

  name        = "${local.name}-db-subnet-group"
  description = "Private subnets for ${var.project_name}"
  subnet_ids  = aws_subnet.private[*].id

  tags = { Name = "${local.name}-db-subnet-group" }
}

resource "aws_db_instance" "main" {
  count = var.enable_rds ? 1 : 0

  identifier     = "${local.name}-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.rds_instance_class

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main[0].name
  vpc_security_group_ids = [aws_security_group.db.id]

  # The database has no public endpoint and no route to an internet gateway.
  publicly_accessible = false

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false

  auto_minor_version_upgrade = true
  apply_immediately          = true

  tags = { Name = "${local.name}-db" }
}
