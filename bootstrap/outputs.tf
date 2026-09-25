output "role_arn" {
  description = "The pipeline's role: set as TF_AWS_ROLE_ARN on the management and management-plan GitHub Environments (scripts/bootstrap.sh does)."
  value       = aws_iam_role.ci.arn
}

output "state_bucket" {
  description = "Where infrastructure/management keeps its state, under identity/."
  value       = aws_s3_bucket.state.bucket
}

output "account_id" {
  description = "The management account this was applied in."
  value       = data.aws_caller_identity.current.account_id
}
