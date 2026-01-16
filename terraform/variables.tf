variable "resource_prefix" {
  type        = string
  description = "Prefix used for naming all resources"
}

variable "region" {
  type = string
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI profile to use for Terraform operations"
}

variable "zone_id" {
  type        = string
  description = "Route53 Hosted Zone ID"
}

variable "domain_name" {
  type        = string
  description = "FQDN for Vault (e.g., vault.example.com)"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "allowed_additional_cidrs" {
  type        = list(string)
  default     = []
  description = "Additional CIDRs allowed to access HTTPS (ALB:443). Current local IP /32 is always added automatically."
}

variable "vault_version" {
  type    = string
  default = "1.21.2"
}

variable "owner" {
  type        = string
  description = "Owner tag for all resources"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources"
  default     = {}
}

variable "enable_ssm_access" {
  type        = bool
  description = "Enable SSM Session Manager access to the instance. Manually figure out SSH if you set this to false"
  default     = true
}

