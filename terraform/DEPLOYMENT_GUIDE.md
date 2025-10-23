# Student Portal AWS Infrastructure - Deployment Guide

## Project Overview

This Terraform infrastructure deploys a production-ready Student Portal application on AWS with:

- **ECS Fargate** - Containerized application with auto-scaling
- **Application Load Balancer** - With HTTPS/SSL support
- **RDS PostgreSQL** - Managed database with encryption
- **Route 53** - DNS management with automatic SSL certificates
- **VPC** - Complete network architecture with public/private subnets
- **Security** - Security groups, KMS encryption, Secrets Manager

**Environments:**
- Dev: `dev.studentportal.ofagbule.cloud`
- Prod: `prod.studentportal.ofagbule.cloud`

---

## Pre-Deployment Requirements

### 1. AWS Account Setup

Ensure you have:
- AWS CLI installed and configured
- AWS credentials with appropriate permissions (AdministratorAccess recommended for first deployment)
- Terraform 1.5.7 installed

```bash
# Verify AWS CLI
aws sts get-caller-identity

# Verify Terraform
terraform version
```

### 2. Create S3 Bucket for Terraform State

Create an S3 bucket in **ap-southeast-2** region:

```bash
aws s3api create-bucket \
  --bucket ofagbule-terraform-state \
  --region ap-southeast-2 \
  --create-bucket-configuration LocationConstraint=ap-southeast-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket ofagbule-terraform-state \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket ofagbule-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket ofagbule-terraform-state \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

### 3. Create DynamoDB Table for State Locking (Optional but Recommended)

```bash
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-southeast-2
```

If you create the DynamoDB table, add this line to both `vars/dev.tfbackend` and `vars/prod.tfbackend`:
```hcl
dynamodb_table = "terraform-state-lock"
```

### 4. Route 53 Hosted Zone Setup

**CRITICAL STEP:**

1. Create a Route 53 hosted zone in AWS Console or CLI:

```bash
aws route53 create-hosted-zone \
  --name ofagbule.cloud \
  --caller-reference $(date +%s)
```

2. Get the nameservers:

```bash
aws route53 list-hosted-zones-by-name --dns-name ofagbule.cloud
```

3. **Update GoDaddy nameservers:**
   - Log in to your GoDaddy account
   - Go to your domain `ofagbule.cloud`
   - Change nameservers to the 4 AWS Route 53 nameservers
   - Wait 24-48 hours for DNS propagation (usually faster)

4. Verify DNS propagation:

```bash
dig NS ofagbule.cloud
# Should show AWS nameservers
```

### 5. Create KMS Key for RDS Encryption

```bash
# Create KMS key
aws kms create-key \
  --description "RDS encryption key for Student Portal" \
  --region ap-southeast-2

# Create alias (replace KEY_ID with the actual key ID from above)
aws kms create-alias \
  --alias-name alias/rds-studentportal \
  --target-key-id <KEY_ID> \
  --region ap-southeast-2
```

**Note:** The Terraform code expects a KMS key with alias `alias/rds`. You may need to update `data.tf` to use the correct alias name.

### 6. Create ECR Repository and Push Docker Image

```bash
# Create ECR repository
aws ecr create-repository \
  --repository-name ecs-studentportal \
  --region ap-southeast-2

# Get your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Authenticate Docker to ECR
aws ecr get-login-password --region ap-southeast-2 | \
  docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.ap-southeast-2.amazonaws.com

# Build and tag the image (you'll need the Student Portal application code)
# Assuming you have the Dockerfile in the application directory
cd /path/to/studentportal-app
docker build --platform linux/amd64 -t ecs-studentportal:1.0 .

# Tag the image for ECR
docker tag ecs-studentportal:1.0 \
  ${AWS_ACCOUNT_ID}.dkr.ecr.ap-southeast-2.amazonaws.com/ecs-studentportal:1.0

# Push to ECR
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.ap-southeast-2.amazonaws.com/ecs-studentportal:1.0
```

---

## Deployment Steps

### Development Environment

```bash
# Initialize Terraform with dev backend
terraform init -backend-config=vars/dev.tfbackend

# Review the plan
terraform plan -var-file=vars/dev.tfvars

# Apply the infrastructure
terraform apply -var-file=vars/dev.tfvars

# Verify deployment
echo "Your dev application will be available at: https://dev.studentportal.ofagbule.cloud"
```

### Production Environment

```bash
# Initialize Terraform with prod backend
terraform init -backend-config=vars/prod.tfbackend -reconfigure

# Review the plan
terraform plan -var-file=vars/prod.tfvars

# Apply the infrastructure
terraform apply -var-file=vars/prod.tfvars

# Verify deployment
echo "Your prod application will be available at: https://prod.studentportal.ofagbule.cloud"
```

---

## Post-Deployment Verification

### 1. Check ECS Service

```bash
# For dev
aws ecs describe-services \
  --cluster dev-studentportal-cluster \
  --services dev-studentportal-service \
  --region ap-southeast-2

# For prod
aws ecs describe-services \
  --cluster prod-studentportal-cluster \
  --services prod-studentportal-service \
  --region ap-southeast-2
```

### 2. Check ALB Health

```bash
# Get ALB DNS name
aws elbv2 describe-load-balancers \
  --region ap-southeast-2 \
  --query 'LoadBalancers[?contains(LoadBalancerName, `studentportal`)].DNSName'

# Check target health
aws elbv2 describe-target-health \
  --target-group-arn <TARGET_GROUP_ARN> \
  --region ap-southeast-2
```

### 3. Test the Application

```bash
# HTTP (should work)
curl http://dev.studentportal.ofagbule.cloud/login

# HTTPS (should work after certificate validation)
curl https://dev.studentportal.ofagbule.cloud/login
```

### 4. Monitor CloudWatch Logs

```bash
aws logs tail /ecs/dev-studentportal-task-def --follow --region ap-southeast-2
```

---

## Load Testing (Optional)

Test your auto-scaling configuration:

```bash
# Dev environment
docker run --rm williamyeh/hey \
  -n 10000 \
  -c 200 \
  https://dev.studentportal.ofagbule.cloud/login

# Prod environment
docker run --rm williamyeh/hey \
  -n 50000 \
  -c 500 \
  https://prod.studentportal.ofagbule.cloud/login
```

Watch ECS tasks scale in CloudWatch or AWS Console.

---

## Troubleshooting

### Certificate Validation Pending

If HTTPS doesn't work immediately:

1. Check ACM certificate status:
```bash
aws acm list-certificates --region ap-southeast-2
```

2. Verify Route 53 validation records were created
3. Wait 5-10 minutes for validation to complete

### ECS Tasks Not Starting

1. Check CloudWatch logs:
```bash
aws logs tail /ecs/dev-studentportal-task-def --follow --region ap-southeast-2
```

2. Verify ECR image exists and tasks can pull it
3. Check IAM role permissions

### Cannot Connect to Database

1. Verify security group rules (RDS SG should allow 5432 from ECS SG)
2. Check RDS instance status
3. Review database connection string in ECS task environment variables

### DNS Not Resolving

1. Verify Route 53 hosted zone exists
2. Confirm GoDaddy nameservers updated
3. Wait for DNS propagation (up to 48 hours)
4. Test with `dig` or `nslookup`

---

## Cost Estimation (Sydney Region - ap-southeast-2)

### Dev Environment (Monthly)
- ECS Fargate (1-2 tasks): ~$20-40
- ALB: ~$25
- RDS db.t3.micro: ~$20
- NAT Gateway: ~$45
- Route 53: ~$1
- Data Transfer: ~$10-20
- **Total: ~$120-150/month**

### Prod Environment (Monthly)
- ECS Fargate (2-5 tasks): ~$60-120
- ALB: ~$25
- RDS db.t3.medium: ~$70
- NAT Gateway: ~$45
- Route 53: ~$1
- Data Transfer: ~$20-50
- **Total: ~$220-310/month**

**Tips to reduce costs:**
- Stop dev environment when not in use
- Use Fargate Spot for dev
- Consider Aurora Serverless for dev
- Enable S3 lifecycle policies

---

## Cleanup / Destroy

**WARNING:** This will delete all resources and data!

```bash
# Dev environment
terraform destroy -var-file=vars/dev.tfvars

# Prod environment
terraform destroy -var-file=vars/prod.tfvars
```

**Manual cleanup required:**
- S3 bucket (if not empty)
- ECR repository
- Route 53 hosted zone (if you want to keep domain)
- KMS keys (have a 30-day waiting period)

---

## Production Enhancements for LinkedIn Post

Consider adding these improvements before posting:

1. **Add WAF** - Web Application Firewall for security
2. **CloudWatch Alarms** - For monitoring and alerting
3. **Backup Strategy** - Automated RDS snapshots
4. **CI/CD Pipeline** - GitHub Actions or AWS CodePipeline
5. **Blue/Green Deployments** - Zero-downtime deployments
6. **Multi-Region Setup** - For disaster recovery
7. **CDN with CloudFront** - For better performance
8. **Container Image Scanning** - ECR image scanning
9. **Cost Optimization** - Savings plans, reserved instances
10. **Documentation** - Architecture diagrams

---

## Support

For issues related to:
- Terraform code: Check the bootcamp resources
- AWS services: AWS Support or AWS documentation
- Domain/DNS: GoDaddy support

---

## License

This infrastructure code is for educational purposes as part of a DevOps bootcamp.
