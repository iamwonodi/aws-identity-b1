# ------------------------------------------------------------------------------
# BOOTSTRAP: WHAT THE PIPELINE NEEDS BEFORE IT CAN RUN
#
# Applied once, by an administrator, in the Organization's management account
# (scripts/bootstrap.sh). Creates the state bucket, GitHub's OIDC provider and
# the role this repository's pipeline assumes.
#
# The role administers IAM Identity Center: users, groups, permission sets and
# their assignment to accounts. That is power over who may sign in to every
# account, which is why only this repository's reviewed GitHub Environments may
# assume it, and why its changes need review.
#
# Its own state is local (bootstrap/terraform.tfstate, never committed): keep
# it, or import the three resources before running it again.
# ------------------------------------------------------------------------------

locals {
  state_bucket = "${var.project_name}-management-tfstate"
  role_name    = "${var.project_name}-identity-ci"
  oidc_url     = "token.actions.githubusercontent.com"
}

data "aws_caller_identity" "current" {}

# ---- state ---------------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ---- GitHub OIDC ---------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://${local.oidc_url}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://${local.oidc_url}"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# ---- the pipeline's role ---------------------------------------------------------

resource "aws_iam_role" "ci" {
  name                 = local.role_name
  description          = "CI role for ${var.github_repository}: administers IAM Identity Center."
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = local.oidc_provider_arn }
      Condition = {
        StringEquals = {
          "${local.oidc_url}:aud" = "sts.amazonaws.com"
          # This repository's two GitHub Environments, and nothing else: not a
          # branch, not a pull request from a fork.
          "${local.oidc_url}:sub" = [
            "repo:${var.github_repository}:environment:management",
            "repo:${var.github_repository}:environment:management-plan",
          ]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "ci" {
  name = "identity-center"
  role = aws_iam_role.ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "IdentityCenter"
        Effect   = "Allow"
        Action   = ["sso:*", "sso-directory:*", "identitystore:*"]
        Resource = "*"
      },
      # Identity Center reads the Organization's accounts to assign to them.
      {
        Sid    = "ReadTheOrganization"
        Effect = "Allow"
        Action = [
          "organizations:DescribeAccount", "organizations:DescribeOrganization", "organizations:ListAccounts",
          "organizations:ListAWSServiceAccessForOrganization", "organizations:ListDelegatedAdministrators",
        ]
        Resource = "*"
      },
      {
        Sid      = "StateObjects"
        Effect   = "Allow"
        Action   = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.state.arn}/identity/*"
      },
      {
        Sid       = "StateList"
        Effect    = "Allow"
        Action    = ["s3:GetBucketLocation", "s3:ListBucket"]
        Resource  = aws_s3_bucket.state.arn
        Condition = { StringLike = { "s3:prefix" = ["identity", "identity/*"] } }
      },
    ]
  })
}
