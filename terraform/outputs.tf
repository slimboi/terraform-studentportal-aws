output "dev_app_url" {
  description = "Development environment URL"
  value       = "https://dev.${var.ecs_app_values.subdomain_name}.${var.ecs_app_values.domain_name}"
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.alb.dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.ecr.repository_url
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.postgres.endpoint
  sensitive   = true
}