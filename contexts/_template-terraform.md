# Terraform Patterns & Best Practices

> **Purpose:** Terraform code standards for consistency and maintainability.

---

## 📦 Project Structure

```
project/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── terraform.tfvars
│   ├── staging/
│   └── prod/
├── modules/
│   ├── networking/
│   ├── compute/
│   └── database/
├── .terraform-version
├── .tflint.hcl
└── README.md
```

---

## 🎯 Module Standards

### When to create a module
- ✅ Resources repeated in several places
- ✅ Configurations with complex dependencies
- ✅ Standardised team patterns

### Module layout
```
modules/[module-name]/
├── main.tf           # Main resources
├── variables.tf      # Input variables
├── outputs.tf        # Output values
├── versions.tf       # Provider requirements
├── README.md         # Documentation
└── examples/         # Usage examples
```

### Internal modules
```hcl
# Use modules from the company repository
module "vpc" {
  source = "git::https://github.com/[company]/terraform-modules.git//modules/vpc?ref=v1.0.0"

  # Always pin a tag/version, NEVER 'main' or 'master'
}
```

---

## 📝 Code Style

### Naming Conventions

**Resources:**
```hcl
# Format: [resource-type]_[env]_[name]
resource "aws_instance" "prod_api_server" {
  # ...
}

# For one-off resources, drop env if it applies to all
resource "aws_s3_bucket" "logs" {
  # ...
}
```

**Variables:**
```hcl
# snake_case, descriptivos
variable "vpc_cidr_block" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}
```

**Locals:**
```hcl
locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Project     = var.project_name
  }

  # Name that describes the purpose
  availability_zones = data.aws_availability_zones.available.names
}
```

### File Organization

**variables.tf:**
```hcl
# Group by category, sort alphabetically
# 1. Required variables (no default)
# 2. Optional variables (with default)

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}
```

**outputs.tf:**
```hcl
# Descriptive outputs, with comments
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}
```

---

## 🔒 State Management

### Backend Configuration

**S3 + DynamoDB (AWS):**
```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state-[company]-[account]"
    key            = "[project]/[env]/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"

    # NEVER access_key/secret_key here
    # Use AWS profiles or IAM roles
  }
}
```

### State Best Practices
- ✅ One state file per environment (dev/staging/prod apart)
- ✅ Encryption enabled
- ✅ Locking enabled (DynamoDB or S3 lockfile)
- ✅ S3 versioning enabled
- ✅ Backup configurado
- ❌ NO compartir state entre proyectos no relacionados

---

## 🔐 Security Practices

### Secrets
```hcl
# ✅ RIGHT: use data sources for secrets
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "prod/database/password"
}

resource "aws_db_instance" "main" {
  password = data.aws_secretsmanager_secret_version.db_password.secret_string
}

# ❌ INCORRECTO: Hardcodear secrets
resource "aws_db_instance" "main" {
  password = "my-password-123"  # ❌ NEVER DO THIS
}
```

### Sensitive Variables
```hcl
variable "database_password" {
  description = "Database master password"
  type        = string
  sensitive   = true  # ✅ Marcar como sensitive
}
```

---

## 📌 Version Pinning

### Provider Versions
```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # Pin major version, allow minor updates
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }
}
```

### Module Versions
```hcl
# ✅ RIGHT: pin a version
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.0"
}

# ❌ WRONG: no version
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
}
```

---

## 🎯 Validation & Testing

### Input Validation
```hcl
variable "instance_type" {
  description = "EC2 instance type"
  type        = string

  validation {
    condition     = contains(["t3.micro", "t3.small", "t3.medium"], var.instance_type)
    error_message = "Instance type must be t3.micro, t3.small, or t3.medium."
  }
}
```

### Pre-commit Checks
```bash
# Run before every commit:
terraform fmt -recursive
terraform validate
tflint  # If available
```

---

## 📋 Workflow

### Standard Workflow
```bash
# 1. Format code
terraform fmt -recursive

# 2. Initialize
terraform init

# 3. Validate
terraform validate

# 4. Plan (review the changes)
terraform plan -out=tfplan

# 5. Apply (ONLY after peer review)
terraform apply tfplan

# 6. Cleanup
rm tfplan
```

### Plan Review Checklist
- [ ] Cambios esperados vs plan
- [ ] No resources unexpectedly destroyed
- [ ] Naming conventions correctas
- [ ] Tags aplicados
- [ ] Security groups restrictivos
- [ ] No secrets expuestos
- [ ] Cambios documentados

---

## 🚫 Anti-Patterns

❌ **AVOID:**
```hcl
# 1. count/for_each without toset() when needed
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)  # ⚠️ Puede causar issues
}

# 2. Inline policies largas (extraer a locals)
resource "aws_iam_role" "example" {
  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    ...  # 50 lines of JSON
  }
  EOF
}

# 3. Resources without lifecycle rules when they need them
resource "aws_instance" "main" {
  # Without lifecycle, it is recreated on every AMI change
}

# 4. Data sources without error handling
data "aws_ami" "latest" {
  most_recent = true
  # What happens if no AMI is found?
}
```

---

## 📝 Documentation Standards

### Module README
```markdown
# Module Name

## Description
[What this module does]

## Usage
```hcl
module "example" {
  source = "..."

  variable1 = "value"
}
```

## Requirements
- Terraform version
- Provider versions

## Inputs
| Name | Description | Type | Default | Required |

## Outputs
| Name | Description |
```

---

## 🔄 Migration & Refactoring

### Moved Blocks (Terraform 1.1+)
```hcl
# To rename resources without destroy/create
moved {
  from = aws_instance.old_name
  to   = aws_instance.new_name
}
```

### Import Existing Resources
```bash
terraform import aws_instance.example i-1234567890abcdef0
```

---

## 📝 Notas

- **Last updated:** [DATE]
- **Herramientas recomendadas:** terraform-docs, tflint, checkov
- **CI/CD:** run the validation in the pipeline
