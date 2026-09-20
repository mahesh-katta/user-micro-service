# ---------------------------------------------------------------------------
# Container registry
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name = var.project_name

  # Immutable tags mean a given tag can never be overwritten. Every deploy is
  # therefore tied to one exact commit and can be rolled back to by digest.
  # This is also why the pipeline tags by git SHA and never pushes "latest":
  # "latest" is not a version, it is a moving target.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  # Lets `terraform destroy` clean up even when images are present.
  force_delete = true

  tags = { Name = "${var.project_name}-ecr" }
}

# Storage beyond the free tier is billed per GB-month, and a pipeline that
# pushes on every commit will accumulate images quickly.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the 10 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
