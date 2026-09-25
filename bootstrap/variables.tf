variable "project_name" {
  type        = string
  description = "Project name, as core was set up with."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-16 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "aws_region" {
  type        = string
  description = "The Region of the Organization's IAM Identity Center, where the state bucket lives too."
}

variable "github_repository" {
  type        = string
  description = "This repository, OWNER/REPOSITORY: only its management and management-plan GitHub Environments may assume the role."

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository must be OWNER/REPOSITORY."
  }
}

variable "create_oidc_provider" {
  type        = bool
  default     = true
  description = "Create GitHub's OIDC provider in the management account. False if the account already has one (an account holds one per URL)."
}
