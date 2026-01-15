variable "domain_name" {
  type = string
}

variable "zone_id" {
  type        = string
  description = "Route53 hosted zone ID (required only if configure_route53 = true)"
  default     = null
}

variable "configure_route53" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
