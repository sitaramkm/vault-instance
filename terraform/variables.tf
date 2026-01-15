variable "region" {
  type = string
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI profile to use for Terraform operations"
}

variable "name" {
  type = string
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

variable "tags" {
  type    = map(string)
  default = {}
}

variable "configure_route53" {
  type        = bool
  description = "Whether Terraform should manage Route53 records and ACM DNS validation"
  default     = true
}

variable "enable_ssm_access" {
  type        = bool
  description = "Enable SSM Session Manager access to the instance. Manually figure out SSH if you set this to false"
  default     = true
}
