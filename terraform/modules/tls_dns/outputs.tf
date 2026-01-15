output "certificate_arn" {
  value = var.configure_route53 ? aws_acm_certificate_validation.this[0].certificate_arn : aws_acm_certificate.this.arn
}
