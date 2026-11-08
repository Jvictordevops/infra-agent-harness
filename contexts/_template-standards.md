# Platform Engineering Standards

> **Purpose:** Company conventions shared by every project.
> This file works with Claude Code and GitHub Copilot alike.

---

## 🏷️ Naming Conventions

### AWS Resources

**EC2 Instances:**
```
Format:  ec2-[company]-[env]-[app]-[number]
Example: ec2-acme-prod-api-01
```

**S3 Buckets:**
```
Format:  s3-[company]-[env]-[purpose]
Example: s3-acme-prod-logs
```

**RDS Databases:**
```
Format:  rds-[company]-[env]-[app]-[engine]
Example: rds-acme-prod-api-postgres
```

**Lambda Functions:**
```
Format:  lambda-[company]-[env]-[function]
Example: lambda-acme-prod-image-processor
```

**Security Groups:**
```
Format:  sg-[company]-[env]-[purpose]
Example: sg-acme-prod-alb
```

**IAM Roles:**
```
Format:  role-[service]-[env]-[purpose]
Example: role-ec2-prod-app-access
```

### Kubernetes Resources

**Namespaces:**
```
Format:  [env]-[team]-[app]
Example: prod-platform-api
```

**Deployments:**
```
Format:  [app]-[component]
Example: api-backend
```

**Services:**
```
Format:  [app]-[component]-svc
Example: api-backend-svc
```

---

## 🏷️ Required Tags (AWS)

**Mandatory on ALL resources:**
```yaml
Environment: dev | staging | prod
Team: platform | data | app | [others]
CostCenter: [cost centre code]
ManagedBy: terraform | manual
Project: [project name]
Owner: [owner e-mail]
```

**Optional but recommended:**
```yaml
Backup: true | false
Compliance: pci | hipaa | sox | none
DataClassification: public | internal | confidential | restricted
```

---

## 🔐 Security Baseline

### Encryption
- ✅ **At Rest:** AES-256 minimum
- ✅ **In Transit:** TLS 1.2+ mandatory
- ✅ **S3:** Server-Side Encryption enabled by default
- ✅ **RDS:** Encryption mandatory in prod/staging
- ✅ **EBS:** Encrypted volumes

### IAM Best Practices
- ✅ Use IAM roles, NOT IAM users, for services
- ✅ Principle of Least Privilege
- ✅ MFA mandatory for human access
- ✅ Rotate credentials every 90 days
- ❌ NO secrets hard-coded in code
- ❌ NO access keys on EC2 (use instance profiles)

### Secrets Management
- ✅ AWS Secrets Manager or Parameter Store
- ✅ Standard prefix: `/[env]/[service]/[secret-name]`
- ✅ Automatic rotation when possible
- ❌ NO secrets in plain-text environment variables
- ❌ NO secrets in git repositories

### Network Security
- ✅ Security groups with specific rules (NO 0.0.0.0/0 in prod)
- ✅ NACLs as an extra security layer
- ✅ VPC Flow Logs enabled
- ✅ Private subnets for backend resources
- ✅ Bastion or SSM Session Manager for access

### Backup & DR
- ✅ Automatic backups enabled
- ✅ Minimum retention: 30 days (adjust to compliance)
- ✅ Cross-region backup for critical resources
- ✅ RTO/RPO documented per service

---

## 📋 Anti-Patterns (AVOID)

❌ **Do NOT:**
- Resources without tags
- Hard-coded IPs, endpoints, secrets
- Security groups with 0.0.0.0/0 in production
- Using the `default` VPC/subnets/security groups
- Publicly accessible RDS
- Public S3 buckets without a reason
- IAM policies with `*` in production
- Resources outside the naming convention
- Applying infrastructure changes without peer review

---

## 🎯 Workflow Standards

### Pre-Deployment Checklist
- [ ] Code reviewed (peer review)
- [ ] Naming conventions applied
- [ ] Mandatory tags present
- [ ] Security baseline met
- [ ] Documentation updated
- [ ] Rollback plan defined

### Post-Deployment
- [ ] Check the resources were created correctly
- [ ] Check the tags applied
- [ ] Confirm backups are configured
- [ ] Update documentation if needed
- [ ] Notify stakeholders

---

## 📝 Notes

- **Last updated:** [DATE]
- **Contact:** [OWNING TEAM]
- **Exceptions:** need approval from [ROLE]
