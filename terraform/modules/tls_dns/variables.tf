variable "domain_name" {
  type = string
}

variable "zone_id" {
  type        = string
  description = "Route53 hosted zone ID"
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
