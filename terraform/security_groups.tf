# ---------------------------------------------------------------------------
# Security groups
#
# Rules are declared as individual aws_vpc_security_group_*_rule resources
# rather than inline blocks. Inline blocks silently replace the whole rule set
# on every change; separate resources give a readable plan and let the database
# group be created with no egress rules at all.
# ---------------------------------------------------------------------------

# --- Application -----------------------------------------------------------

resource "aws_security_group" "app" {
  name        = "${local.name}-app-sg"
  description = "Application instance: inbound HTTP from the internet, SSH only if explicitly allowed"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-app-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_http" {
  count = length(var.app_ingress_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "Application HTTP"
  cidr_ipv4         = var.app_ingress_cidrs[count.index]
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
}

# Empty by default. Administration goes through SSM Session Manager, which
# needs no inbound rule at all because the agent opens an outbound connection.
resource "aws_vpc_security_group_ingress_rule" "app_ssh" {
  count = length(var.admin_ssh_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "SSH from an explicitly allowed administrator network"
  cidr_ipv4         = var.admin_ssh_cidrs[count.index]
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

# Outbound is needed to reach ECR, SSM and the OS package mirrors.
resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "Outbound to ECR, SSM and package mirrors"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# --- Database --------------------------------------------------------------
#
# This is the isolation that matters. The only ingress rule references the
# application's security group by ID, not by CIDR: membership of the app group
# is what grants access, so an instance that is merely inside the same subnet
# still cannot reach the database. There are no egress rules, so the database
# cannot initiate a connection to anything.

resource "aws_security_group" "db" {
  name        = "${local.name}-db-sg"
  description = "PostgreSQL: reachable only from the application security group, no egress"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-db-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from the application security group only"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}
