variable "project_name" {
  type        = string
  description = "Project name, as core was set up with. Set by scripts/init-identity.sh."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-16 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "aws_region" {
  type        = string
  description = "The Region of the Organization's IAM Identity Center. Keep it in sync with backend.tf; scripts/init-identity.sh sets both."

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be an AWS Region such as af-south-1."
  }
}
