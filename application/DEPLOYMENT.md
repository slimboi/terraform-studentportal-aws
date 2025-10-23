# Flask Student Portal - Deployment Guide

A comprehensive guide for deploying the Flask Student Portal application locally, with Docker, and on AWS ECS.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Application Overview](#application-overview)
- [Local Development Setup](#local-development-setup)
- [Docker Deployment](#docker-deployment)
- [AWS ECS Deployment](#aws-ecs-deployment)
- [Monitoring and Observability](#monitoring-and-observability)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### For Local Development
- Python 3.11 or higher
- PostgreSQL 15
- pip (Python package manager)
- virtualenv

### For Docker Deployment
- Docker Engine 20.10+
- Docker Compose 2.0+

### For AWS ECS Deployment
- AWS Account with appropriate permissions
- AWS CLI configured with credentials
- Docker for building images
- Access to create:
  - ECR repositories
  - ECS clusters
  - RDS databases
  - VPC resources
  - Application Load Balancers

---

## Application Overview

**Tech Stack:**
- **Framework:** Flask (Python)
- **Database:** PostgreSQL
- **Authentication:** Flask-Login
- **Metrics:** Prometheus (available at `/metrics`)
- **Logging:** JSON structured logging
- **Port:** 8000

**Key Features:**
- Student portal management
- User authentication and authorization
- Real-time metrics collection
- Health monitoring ready

---

## Local Development Setup

### Step 1: Set Up PostgreSQL Database

```bash
# Run PostgreSQL container
docker run -d \
  --name attendance-db \
  -e POSTGRES_PASSWORD=password \
  -e POSTGRES_DB=mydb \
  -p 5432:5432 \
  postgres:15

# Verify database is running
docker ps | grep attendance-db
```

### Step 2: Set Up Python Environment

```bash
# Create virtual environment
python3 -m venv venv

# Activate virtual environment
# On macOS/Linux:
source venv/bin/activate
# On Windows:
# venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### Step 3: Configure Environment

```bash
# Export database connection string
export DB_LINK="postgresql://postgres:password@localhost:5432/mydb"
```

### Step 4: Run the Application

```bash
# Start the Flask application
python run.py
```

The application will be available at: `http://localhost:8000`

### Step 5: Verify Installation

```bash
# Check application health
curl http://localhost:8000

# Check Prometheus metrics
curl http://localhost:8000/metrics
```

---

## Docker Deployment

### Option 1: Docker Compose (Recommended for Local Development)

This approach automatically sets up both the application and PostgreSQL database.

```bash
# Build and start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down

# Stop and remove volumes (clean slate)
docker-compose down -v
```

**Services Started:**
- **app:** Flask application on port 8000
- **db:** PostgreSQL database on port 5432

**Access the Application:**
- Application: `http://localhost:8000`
- Metrics: `http://localhost:8000/metrics`

### Option 2: Manual Docker Build

```bash
# Build the Docker image
docker build -t student-portal:latest .

# Run PostgreSQL (if not already running)
docker run -d \
  --name attendance-db \
  -e POSTGRES_PASSWORD=password \
  -e POSTGRES_DB=mydb \
  -p 5432:5432 \
  postgres:15

# Run the application container
docker run -d \
  --name student-portal \
  -p 8000:8000 \
  -e DB_LINK="postgresql://postgres:password@host.docker.internal:5432/mydb" \
  student-portal:latest

# View logs
docker logs -f student-portal
```

**Note:** On Linux, replace `host.docker.internal` with your machine's IP address or use Docker networks.

---

## AWS ECS Deployment

### Architecture Overview

```
Internet → ALB → ECS Service (Fargate) → RDS PostgreSQL
                      ↓
                 CloudWatch Logs
```

### Step 1: Create ECR Repository

```bash
# Set your AWS region
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create ECR repository
aws ecr create-repository \
  --repository-name studentportal \
  --region $AWS_REGION

# Note the repository URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/studentportal)
export ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/studentportal"
```

### Step 2: Build and Push Docker Image

```bash
# Authenticate Docker to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_URI

# Build the image
docker build -t student-portal:latest .

# Tag the image
docker tag student-portal:latest ${ECR_URI}:latest
docker tag student-portal:latest ${ECR_URI}:1.0

# Push to ECR
docker push ${ECR_URI}:latest
docker push ${ECR_URI}:1.0
```

### Step 3: Create RDS Database

#### Using AWS Console:
1. Navigate to RDS Console
2. Click "Create database"
3. Choose:
   - **Engine:** PostgreSQL 15
   - **Template:** Production (or Dev/Test for non-prod)
   - **DB instance identifier:** student-portal-db
   - **Master username:** postgres
   - **Master password:** (create a secure password)
   - **DB name:** mydb
   - **VPC:** Select your VPC
   - **Public access:** No
   - **VPC security group:** Create new (allow port 5432 from ECS tasks)
4. Click "Create database"
5. Note the **Endpoint** (e.g., `student-portal-db.xxxxx.us-east-1.rds.amazonaws.com`)

#### Using AWS CLI:
```bash
# Create DB subnet group first
aws rds create-db-subnet-group \
  --db-subnet-group-name student-portal-subnet-group \
  --db-subnet-group-description "Subnet group for student portal" \
  --subnet-ids subnet-xxxxx subnet-yyyyy

# Create RDS instance
aws rds create-db-instance \
  --db-instance-identifier student-portal-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 15.4 \
  --master-username postgres \
  --master-user-password YOUR_SECURE_PASSWORD \
  --allocated-storage 20 \
  --db-name mydb \
  --vpc-security-group-ids sg-xxxxx \
  --db-subnet-group-name student-portal-subnet-group \
  --no-publicly-accessible

# Wait for database to be available
aws rds wait db-instance-available --db-instance-identifier student-portal-db
```

### Step 4: Create ECS Cluster

#### Using AWS Console:
1. Go to ECS Console
2. Click "Create Cluster"
3. Choose:
   - **Cluster name:** student-portal-cluster
   - **Infrastructure:** AWS Fargate
   - **Monitoring:** Enable Container Insights (optional)
4. Click "Create"

#### Using AWS CLI:
```bash
aws ecs create-cluster \
  --cluster-name student-portal-cluster \
  --region $AWS_REGION
```

### Step 5: Create Task Definition

Create a file named `task-definition.json`:

```json
{
  "family": "student-portal-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::YOUR_ACCOUNT_ID:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "student-portal",
      "image": "YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/studentportal:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "DB_LINK",
          "value": "postgresql://postgres:YOUR_PASSWORD@YOUR_RDS_ENDPOINT:5432/mydb"
        },
        {
          "name": "FLASK_APP",
          "value": "app.py"
        },
        {
          "name": "FLASK_RUN_PORT",
          "value": "8000"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/student-portal",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8000/ || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

**Register the task definition:**
```bash
# Create CloudWatch log group
aws logs create-log-group --log-group-name /ecs/student-portal

# Register task definition
aws ecs register-task-definition --cli-input-json file://task-definition.json
```

### Step 6: Create Application Load Balancer

#### Using AWS Console:
1. Go to EC2 → Load Balancers
2. Click "Create Load Balancer" → Application Load Balancer
3. Configure:
   - **Name:** student-portal-alb
   - **Scheme:** Internet-facing
   - **IP address type:** IPv4
   - **VPC:** Select your VPC
   - **Subnets:** Select at least 2 public subnets
   - **Security group:** Allow HTTP (80) and HTTPS (443)
4. Create Target Group:
   - **Target type:** IP
   - **Protocol:** HTTP
   - **Port:** 8000
   - **Health check path:** `/login`
5. Complete ALB creation

### Step 7: Create ECS Service

#### Using AWS Console:
1. Go to your ECS cluster
2. Click "Create" under Services
3. Configure:
   - **Launch type:** Fargate
   - **Task definition:** student-portal-task
   - **Service name:** student-portal-service
   - **Number of tasks:** 2
   - **Deployment type:** Rolling update
4. Configure networking:
   - **VPC:** Select your VPC
   - **Subnets:** Select private subnets
   - **Security group:** Allow port 8000 from ALB
5. Configure Load Balancer:
   - **Load balancer type:** Application Load Balancer
   - **Load balancer:** student-portal-alb
   - **Container to load balance:** student-portal:8000
   - **Target group:** Select your target group
6. Click "Create"

#### Using AWS CLI:
```bash
aws ecs create-service \
  --cluster student-portal-cluster \
  --service-name student-portal-service \
  --task-definition student-portal-task \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxxxx,subnet-yyyyy],securityGroups=[sg-xxxxx],assignPublicIp=DISABLED}" \
  --load-balancers "targetGroupArn=arn:aws:elasticloadbalancing:REGION:ACCOUNT:targetgroup/NAME/ID,containerName=student-portal,containerPort=8000"
```

### Step 8: Configure Security Groups

**RDS Security Group:**
- **Inbound:** Port 5432 from ECS tasks security group

**ECS Tasks Security Group:**
- **Inbound:** Port 8000 from ALB security group
- **Outbound:** Port 5432 to RDS security group
- **Outbound:** Port 443 to 0.0.0.0/0 (for AWS API calls)

**ALB Security Group:**
- **Inbound:** Port 80 from 0.0.0.0/0
- **Inbound:** Port 443 from 0.0.0.0/0 (if using HTTPS)
- **Outbound:** Port 8000 to ECS tasks security group

### Step 9: Access Your Application

```bash
# Get ALB DNS name
aws elbv2 describe-load-balancers \
  --names student-portal-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text
```

Access your application at: `http://YOUR-ALB-DNS-NAME`

### Step 10: (Optional) Configure Custom Domain

1. Register a domain or use existing domain
2. Create Route 53 hosted zone
3. Create an A record (Alias) pointing to your ALB
4. Configure SSL/TLS certificate in ACM
5. Add HTTPS listener to ALB

---

## Monitoring and Observability

### Prometheus Metrics

The application exposes Prometheus metrics at `/metrics` endpoint:

```bash
# Access metrics
curl http://YOUR-APP-URL/metrics
```

**Available Metrics:**
- `http_requests_total` - Total HTTP requests by method, endpoint, and status
- `request_duration_seconds` - Request duration histogram by endpoint

### CloudWatch Logs (AWS ECS)

```bash
# View logs
aws logs tail /ecs/student-portal --follow
```

### Application Logs

All requests are logged in JSON format with:
- Method
- Path
- Status code
- Duration

---

## Troubleshooting

### Local Development Issues

**Problem: Database connection refused**
```bash
# Check if PostgreSQL is running
docker ps | grep attendance-db

# Check database logs
docker logs attendance-db

# Verify connection string
echo $DB_LINK
```

**Problem: Port already in use**
```bash
# Find process using port 8000
lsof -i :8000

# Kill the process
kill -9 <PID>
```

### Docker Issues

**Problem: Container exits immediately**
```bash
# Check container logs
docker logs student-portal

# Run container interactively
docker run -it --entrypoint /bin/bash student-portal:latest
```

**Problem: Cannot connect to database from container**
```bash
# Test database connectivity
docker exec -it student-portal ping db

# Check Docker network
docker network ls
docker network inspect flask-student-portal-docker-ecs_test_network
```

### AWS ECS Issues

**Problem: Tasks fail to start**
```bash
# Check task status
aws ecs describe-tasks \
  --cluster student-portal-cluster \
  --tasks TASK-ID

# Check service events
aws ecs describe-services \
  --cluster student-portal-cluster \
  --services student-portal-service
```

**Problem: Health checks failing**
- Verify security groups allow traffic
- Check CloudWatch logs for application errors
- Verify database connection string is correct
- Ensure RDS security group allows connections from ECS tasks

**Problem: Cannot pull image from ECR**
- Verify task execution role has ECR permissions
- Check ECR repository policy
- Ensure image exists in ECR

### Database Connection Issues

**Problem: Connection timeout to RDS**
- Verify RDS security group allows inbound from ECS
- Check VPC routing tables
- Verify RDS endpoint is correct
- Ensure database is in "Available" state

---

## Clean Up AWS Resources

```bash
# Delete ECS service
aws ecs update-service \
  --cluster student-portal-cluster \
  --service student-portal-service \
  --desired-count 0

aws ecs delete-service \
  --cluster student-portal-cluster \
  --service student-portal-service \
  --force

# Delete ECS cluster
aws ecs delete-cluster --cluster student-portal-cluster

# Delete RDS instance (creates final snapshot)
aws rds delete-db-instance \
  --db-instance-identifier student-portal-db \
  --final-db-snapshot-identifier student-portal-final-snapshot

# Delete ALB
aws elbv2 delete-load-balancer --load-balancer-arn YOUR-ALB-ARN

# Delete ECR images and repository
aws ecr batch-delete-image \
  --repository-name studentportal \
  --image-ids imageTag=latest imageTag=1.0

aws ecr delete-repository --repository-name studentportal
```

---

## Support and Resources

- **Application Port:** 8000
- **Database:** PostgreSQL
- **Metrics Endpoint:** `/metrics`
- **Python Version:** 3.11
- **AWS Documentation:** [ECS Fargate](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)

---

## Security Best Practices

1. **Never commit credentials** to version control
2. **Use AWS Secrets Manager** for sensitive data in ECS
3. **Enable encryption** for RDS and ECS task storage
4. **Use private subnets** for ECS tasks and RDS
5. **Implement least privilege** IAM policies
6. **Enable CloudTrail** for audit logging
7. **Use HTTPS** with valid SSL certificates
8. **Regularly update** dependencies and base images
9. **Enable WAF** on Application Load Balancer
10. **Implement database backup** strategy

---

## Next Steps

- Set up CI/CD pipeline with GitHub Actions or AWS CodePipeline
- Implement auto-scaling based on metrics
- Add CloudWatch alarms for monitoring
- Set up centralized logging with CloudWatch Insights
- Implement blue-green deployments
- Add integration tests
- Configure backup and disaster recovery

---

**Version:** 1.0
**Last Updated:** October 2025
