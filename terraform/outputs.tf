output "vault_url" {
  description = "Vault UI URL"
  value       = "https://${var.domain_name}"
}

output "vault_version" {
  description = "Vault version installed on the instance"
  value       = var.vault_version
}

output "instance_public_ip" {
  description = "Public IP of the Vault EC2 instance"
  value       = aws_instance.vault.public_ip
}

output "allowed_cidrs_effective" {
  value = local.allowed_cidrs
}

output "ssm_demo_token_name" {
  value = "/${var.resource_prefix}-ssm/demo_token"
}

output "ssm_root_token_name" {
  value = "/${var.resource_prefix}-ssm/root_token"
}

output "resource_prefix" {
  description = "prefix for all resources. For e.g SSM prefix"
  value       = "/${var.resource_prefix}"
}
