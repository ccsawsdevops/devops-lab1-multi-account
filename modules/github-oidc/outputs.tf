output "role_arn" {
  description = "ARN of the IAM Role created for GitHub Actions"
  value       = aws_iam_role.github_actions.arn
}
