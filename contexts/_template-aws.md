# AWS Conventions & Best Practices

> **Purpose:** Patterns for specific AWS services.

---

## 🌍 Multi-Account Strategy

### Account Structure
```
organization/
├── management/          # Root account (billing, org policies)
├── shared-services/     # DNS, logging, monitoring
├── dev/                 # Development workloads
├── staging/            # Pre-production
├── prod/               # Production workloads
└── security/           # Security tooling, audit logs
```

### Cross-Account Access
```hcl
# Use IAM roles for cross-account access
resource "aws_iam_role" "cross_account" {
  name = "role-crossaccount-[purpose]"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::[source-account-id]:root"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "[random-external-id]"
        }
      }
    }]
  })
}
```

---

## 🏗️ VPC Design

### Standard VPC Structure
```
VPC: 10.0.0.0/16 (dev), 10.1.0.0/16 (staging), 10.2.0.0/16 (prod)
│
├── Public Subnets (10.x.0.0/24, 10.x.1.0/24, 10.x.2.0/24)
│   └── NAT Gateways, Load Balancers, Bastion
│
├── Private App Subnets (10.x.10.0/24, 10.x.11.0/24, 10.x.12.0/24)
│   └── EC2, ECS, Lambda, K8s nodes
│
└── Private Data Subnets (10.x.20.0/24, 10.x.21.0/24, 10.x.22.0/24)
    └── RDS, ElastiCache, Redshift
```

### VPC Best Practices
- ✅ Multi-AZ by default (at least 3 AZs)
- ✅ One NAT gateway per AZ (HA)
- ✅ VPC Flow Logs enabled
- ✅ DNS hostnames enabled
- ✅ Private subnets for workloads
- ❌ NO default VPC

---

## 💻 EC2 Best Practices

### Instance Sizing
```hcl
# Preferir instance families modernas
locals {
  instance_types = {
    dev     = "t3.micro"      # Burstable for dev
    staging = "t3.small"
    prod    = "t3.medium"     # Or m6i/c6i for steady prod
  }
}

# Consider Graviton (ARM) for better cost/performance
# m7g, t4g, c7g
```

### User Data Best Practices
```hcl
resource "aws_instance" "app" {
  # Use templatefile for user data
  user_data = templatefile("${path.module}/user-data.sh", {
    environment = var.environment
    app_version = var.app_version
  })

  # Base64-encode if needed
  user_data_base64 = base64encode(templatefile(...))
}
```

### Instance Metadata (IMDSv2)
```hcl
resource "aws_instance" "app" {
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"   # ✅ Forzar IMDSv2
    http_put_response_hop_limit = 1
  }
}
```

---

## 🗄️ RDS Best Practices

### Standard Configuration
```hcl
resource "aws_db_instance" "main" {
  identifier = "rds-${var.company}-${var.environment}-${var.app}-postgres"

  # Engine
  engine               = "postgres"
  engine_version       = "15.4"
  instance_class       = var.db_instance_class

  # Storage
  allocated_storage     = 100
  max_allocated_storage = 1000  # ✅ Storage autoscaling enabled
  storage_encrypted     = true
  storage_type          = "gp3"

  # Networking
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false  # ✅ NEVER true in prod

  # Backup
  backup_retention_period = var.environment == "prod" ? 30 : 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "mon:04:00-mon:05:00"

  # HA
  multi_az = var.environment == "prod" ? true : false

  # Monitoring
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  performance_insights_enabled    = true
  monitoring_interval             = 60

  # Deletion protection
  deletion_protection = var.environment == "prod" ? true : false

  tags = local.common_tags
}
```

---

## 📦 S3 Best Practices

### Bucket Configuration
```hcl
resource "aws_s3_bucket" "main" {
  bucket = "s3-${var.company}-${var.environment}-${var.purpose}"

  tags = local.common_tags
}

# ✅ Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
      # Or KMS: kms_master_key_id = aws_kms_key.main.arn
    }
  }
}

# ✅ Versioning (especially for prod)
resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = var.environment == "prod" ? "Enabled" : "Suspended"
  }
}

# ✅ Block public access
resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.main.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ✅ Lifecycle rules
resource "aws_s3_bucket_lifecycle_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}
```

---

## ⚡ Lambda Best Practices

### Function Configuration
```hcl
resource "aws_lambda_function" "main" {
  function_name = "lambda-${var.company}-${var.environment}-${var.function_name}"

  # Runtime
  runtime = "python3.11"  # Use a current runtime
  handler = "main.handler"

  # Code
  filename         = "lambda.zip"
  source_code_hash = filebase64sha256("lambda.zip")

  # Execution
  role    = aws_iam_role.lambda.arn
  timeout = 30  # Adjust as needed
  memory_size = 512

  # Networking (if it needs VPC access)
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  # Environment variables
  environment {
    variables = {
      ENVIRONMENT = var.environment
      LOG_LEVEL   = var.environment == "prod" ? "INFO" : "DEBUG"
    }
  }

  # Tracing
  tracing_config {
    mode = "Active"  # ✅ X-Ray enabled
  }

  tags = local.common_tags
}

# ✅ Dead Letter Queue
resource "aws_sqs_queue" "lambda_dlq" {
  name = "lambda-${var.function_name}-dlq"
}

resource "aws_lambda_function_event_invoke_config" "main" {
  function_name = aws_lambda_function.main.function_name

  destination_config {
    on_failure {
      destination = aws_sqs_queue.lambda_dlq.arn
    }
  }

  maximum_retry_attempts = 2
}
```

---

## 🔐 Security Groups

### Naming & Organization
```hcl
# One per purpose, NOT generic
resource "aws_security_group" "alb" {
  name        = "sg-${var.company}-${var.environment}-alb"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "sg-${var.company}-${var.environment}-alb"
  })
}

# ✅ Separate rules (easier to manage)
resource "aws_security_group_rule" "alb_https_ingress" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]  # OK for a public ALB
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from Internet"
}

resource "aws_security_group_rule" "app_from_alb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id  # ✅ Referenciar SG, no CIDR
  security_group_id        = aws_security_group.app.id
  description              = "Traffic from ALB"
}
```

---

## 📊 CloudWatch & Monitoring

### Log Groups
```hcl
resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/${var.service}/${var.environment}/${var.app}"
  retention_in_days = var.environment == "prod" ? 30 : 7

  kms_key_id = aws_kms_key.logs.arn  # ✅ Encrypted logs

  tags = local.common_tags
}
```

### Alarms
```hcl
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.app}-${var.environment}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Triggers when CPU exceeds 80%"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.app.id
  }
}
```

---

## 💰 Cost Optimization

### Right-Sizing
- Use Instance Scheduler for dev/staging (stop outside business hours)
- Consider Spot Instances for fault-tolerant workloads
- Use Savings Plans / Reserved Instances for steady prod
- S3 Intelligent-Tiering for data with changing access

### Tagging for Cost Allocation
```hcl
locals {
  cost_tags = {
    CostCenter = var.cost_center
    Project    = var.project
    Team       = var.team
  }
}
```

---

## 🔄 Disaster Recovery

### Backup Strategy
- RDS: automated backups + manual snapshots before changes
- EC2: AMIs + EBS snapshots
- S3: versioning + cross-region replication for critical data
- DynamoDB: point-in-time recovery enabled

### RTO/RPO per environment
```
Dev:     RTO: 24h, RPO: 24h
Staging: RTO: 4h,  RPO: 4h
Prod:    RTO: 1h,  RPO: 15m
```

---

## 📝 Notas

- **Regiones preferidas:** [us-east-1, eu-west-1, etc.]
- **AWS Organizations:** [OU structure details]
- **Service Control Policies:** [Policies applied]
