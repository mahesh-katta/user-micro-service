variable "project_name" {
  description = "Name prefix applied to every resource."
  type        = string
  default     = "user-service"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.project_name))
    error_message = "project_name must be lowercase alphanumeric with hyphens, starting with a letter."
  }
}

variable "aws_region" {
  description = "AWS region to deploy into. ap-south-1 is Mumbai."
  type        = string
  default     = "ap-south-1"
}

variable "github_repository" {
  description = "GitHub repository in owner/name form. The CI role's trust policy is scoped to this repo, so no other repository can assume it."
  type        = string
  default     = "mahesh-katta/user-micro-service"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository must be in owner/name form."
  }
}

variable "github_allowed_refs" {
  description = "Git refs allowed to assume the deployment role. Defaults to main only, so a pull request from a fork cannot deploy."
  type        = list(string)
  default     = ["refs/heads/main"]
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set to false if the account already has one (an account may only have a single provider per URL)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs for the public subnets, one per availability zone."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs for the private subnets, one per availability zone. These have no route to the internet."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "enable_nat_gateway" {
  description = "Give the private subnets outbound internet access through a NAT gateway. OFF by default: a NAT gateway costs roughly USD 32/month plus data processing, and is the single most common source of a surprise AWS bill. Nothing in this stack needs it."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type. t3.micro is free-tier eligible and has 1 GiB of RAM, which is why user_data provisions a 2 GiB swap file and the containers run under explicit memory limits. Use t3.small if you would rather not run that close to the edge."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GiB. The free tier includes 30 GiB of gp3."
  type        = number
  default     = 20
}

variable "app_ingress_cidrs" {
  description = "CIDRs permitted to reach the application port. Narrow this to your own IP while developing."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "admin_ssh_cidrs" {
  description = "CIDRs permitted to open an SSH session. Empty by default: the instance is administered through AWS Systems Manager Session Manager, so port 22 stays closed and there is no key pair to leak."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

variable "enable_rds" {
  description = "Run PostgreSQL on managed RDS in the private subnets instead of as a container on the instance. OFF by default because RDS is not covered by the current free tier for the whole life of this project. The security group that isolates database traffic is created either way."
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Database name."
  type        = string
  default     = "userservice_db"
}

variable "db_username" {
  description = "Database master username."
  type        = string
  default     = "userservice"
}

variable "rds_instance_class" {
  description = "RDS instance class, used only when enable_rds is true."
  type        = string
  default     = "db.t4g.micro"
}

# ---------------------------------------------------------------------------
# Cost guardrails
# ---------------------------------------------------------------------------

variable "monthly_budget_usd" {
  description = "Monthly spend that triggers budget alerts."
  type        = number
  default     = 5
}

variable "alert_email" {
  description = "Email address that receives budget alerts. Leave empty to skip creating the budget."
  type        = string
  default     = ""
}
