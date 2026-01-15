terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

locals {
  tags = merge({ Name = "${var.resource_prefix}-vault-instance" }, var.tags)
}

module "tls_dns" {
  source = "./modules/tls_dns"

  domain_name       = var.domain_name
  zone_id           = var.zone_id
  configure_route53 = var.configure_route53
  tags              = local.tags
}

# -----------------------------
# Discover current public IP for allowlisting
# -----------------------------
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  my_ip_cidr    = "${chomp(data.http.my_ip.response_body)}/32"
  allowed_cidrs = distinct(concat([local.my_ip_cidr], var.allowed_additional_cidrs))
}

# -----------------------------
# Default VPC + subnets (demo-simple)
# -----------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ALB requires >=2 subnets; default VPC usually provides multiple.
locals {
  alb_subnets = slice(data.aws_subnets.default.ids, 0, min(3, length(data.aws_subnets.default.ids)))
}

# -----------------------------
# Security Groups (NO 0.0.0.0/0 ingress)
# -----------------------------
resource "aws_security_group" "alb" {
  name        = "${var.resource_prefix}-alb-sg"
  description = "ALB SG (restricted HTTPS)"
  vpc_id      = data.aws_vpc.default.id
  tags        = local.tags

  # No inline ingress rules: use aws_security_group_rule below
  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "alb_https" {
  for_each          = toset(local.allowed_cidrs)
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS allowlist"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [each.value]
}

resource "aws_security_group" "ec2" {
  name        = "${var.resource_prefix}-ec2-sg"
  description = "EC2 SG (Vault only from ALB)"
  vpc_id      = data.aws_vpc.default.id
  tags        = local.tags

  ingress {
    description     = "Vault HTTP from ALB only"
    from_port       = 8200
    to_port         = 8200
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------
# KMS for Vault auto-unseal
# -----------------------------
resource "aws_kms_key" "vault_unseal" {
  description             = "Vault auto-unseal KMS key"
  deletion_window_in_days = 7
  tags                    = local.tags
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/${var.resource_prefix}-vault-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

# -----------------------------
# IAM role for EC2 (KMS + SSM Parameter Store)
# -----------------------------
resource "aws_iam_role" "vault" {
  name = "${var.resource_prefix}-role"
  tags = local.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "vault" {
  name = "${var.resource_prefix}-policy"
  role = aws_iam_role.vault.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
        Resource = aws_kms_key.vault_unseal.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "arn:aws:ssm:${var.region}:*:parameter/${var.resource_prefix}-ssm/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "vault" {
  name = "${var.resource_prefix}-instance-profile"
  role = aws_iam_role.vault.name
  tags = local.tags
}

# -----------------------------
# Ubuntu AMI
# -----------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# -----------------------------
# EC2 instance (Vault HTTP only)
# -----------------------------
resource "aws_instance" "vault" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  iam_instance_profile        = aws_iam_instance_profile.vault.name
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = true
  tags                        = local.tags

  user_data = templatefile("${path.module}/user_data.sh", {
    vault_version = var.vault_version
    vault_domain  = var.domain_name
    kms_key_id    = aws_kms_key.vault_unseal.key_id
    region        = var.region
    ssm_prefix    = "/${var.resource_prefix}-ssm"
  })
}

# -----------------------------
# ALB + Target Group + Listener
# -----------------------------
resource "aws_lb" "vault" {
  name               = substr("${var.resource_prefix}-alb", 0, 32)
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.alb_subnets
  tags               = local.tags
}

resource "aws_lb_target_group" "vault" {
  name     = substr("${var.resource_prefix}-tg", 0, 32)
  port     = 8200
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  tags     = local.tags

  health_check {
    path                = "/v1/sys/health"
    matcher             = "200-299,429"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "vault" {
  target_group_arn = aws_lb_target_group.vault.arn
  target_id        = aws_instance.vault.id
  port             = 8200
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.vault.arn
  port              = 443
  protocol          = "HTTPS"

  certificate_arn = module.tls_dns.certificate_arn

  ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vault.arn
  }
}


# -----------------------------
# Route53 Alias A record -> ALB
# -----------------------------
resource "aws_route53_record" "vault" {
  count   = var.configure_route53 ? 1 : 0
  zone_id = var.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.vault.dns_name
    zone_id                = aws_lb.vault.zone_id
    evaluate_target_health = true
  }
}

