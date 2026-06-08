# Architecture ECS Farmily - Haute Disponibilité (Prod)

Génère un diagramme d'architecture AWS ECS Fargate avec les composants suivants :

## Services AWS à inclure

### Externes (gauche du cloud)

- Users (icône utilisateurs générique)
- GitHub Actions (CI/CD)

### Networking

- Application Load Balancer (ALB) - dans les subnets publics
- NAT Gateway (2x, un par AZ)
- VPC avec 2 AZ (ap-northeast-2a, ap-northeast-2c)
- Internet Gateway
- S3 VPC Gateway Endpoint

### Compute (subnets privés)

- ECS Fargate Cluster
- 4 Tasks répartis dans 2 AZ (2 par AZ)
- Container : Spring Boot (port 8080)

### Database (subnets privés)

- RDS PostgreSQL 16.4 (Multi-AZ : Primary + Standby)
- ElastiCache Redis 7.0 (Primary + Replica)

### Storage & CDN

- S3 Bucket (farmily-s3-bucket)
- CloudFront Distribution (OAC vers S3)

### Security

- ACM (Certificate Manager) - pour ALB HTTPS
- IAM ECS Execution Role (ECR Pull, CloudWatch Logs)
- IAM ECS Task Role (S3 Access, Bedrock conditionnel)
- Security Groups (ALB → ECS → RDS/Redis)

### Observability

- CloudWatch Logs (/ecs/prod-app)
- CloudWatch Alarms (CPU, Memory, RDS CPU)
- SNS Topic (alertes)

### AI (conditionnel)

- Amazon Bedrock (Agent, us-west-2, activé par toggle)

### Container Registry

- ECR (farmily-api)

## Connexions à tracer

| Source | Target | Label | Style |
| --- | --- | --- | --- |
| Users | ALB | HTTPS (443) | Solid green |
| Users | CloudFront | HTTPS (443) | Solid green |
| ALB | ECS Tasks | HTTP (8080) | Solid green |
| ECS Tasks | RDS Primary | PostgreSQL (5432) | Solid green |
| ECS Tasks | Redis Primary | Redis (6379) | Solid green |
| ECS Tasks | S3 | VPC Endpoint | Solid green |
| ECS Tasks | Bedrock | InvokeAgent (conditionnel) | Dashed blue |
| RDS Primary | RDS Standby | Sync Replication | Dashed gray |
| Redis Primary | Redis Replica | Async Replication | Dashed gray |
| CloudFront | S3 | OAC (sigv4) | Solid green |
| NAT Gateway | Internet | Outbound traffic | Solid green |
| ACM | ALB | TLS Certificate | Dashed gray |
| IAM Execution Role | ECR | Image Pull | Dashed gray |
| IAM Task Role | S3 | Get/Put/Delete | Dashed gray |
| IAM Task Role | Bedrock | InvokeAgent (conditionnel) | Dashed gray |
| ECS Tasks | CloudWatch Logs | Logs | Dashed gray |
| CloudWatch Alarms | SNS | Alert Notification | Dashed orange |
| GitHub Actions | ECR | Docker Push | Solid blue |
| GitHub Actions | ECS | Deploy (update-service) | Solid blue |

## Layout

### VPC (10.1.0.0/16)

```
┌─ Public Subnet A (10.1.1.0/24) ──┐  ┌─ Public Subnet C (10.1.2.0/24) ──┐
│  ALB                               │  │  ALB                               │
│  NAT Gateway A                     │  │  NAT Gateway C                     │
└─────────────────────────────────────┘  └─────────────────────────────────────┘

┌─ Private Subnet A (10.1.10.0/24) ─┐  ┌─ Private Subnet C (10.1.11.0/24) ─┐
│  ECS Task x2                       │  │  ECS Task x2                       │
│  RDS Primary                       │  │  RDS Standby                       │
│  Redis Primary                     │  │  Redis Replica                     │
└─────────────────────────────────────┘  └─────────────────────────────────────┘
```

### Hors VPC

- S3 (accessible via VPC Endpoint)
- CloudFront (edge)
- ECR (accessible via NAT)
- Bedrock (us-west-2, accessible via NAT)
- CloudWatch
- SNS

## Notes

- HTTP(80) redirige vers HTTPS(443) quand ACM est configuré
- TLS Policy : ELBSecurityPolicy-TLS13-1-2-2021-06
- ECS Task Definition géré avec `lifecycle { ignore_changes }` (CI/CD ownership)
- Bedrock activé uniquement si `ai_provider = "bedrock"` dans tfvars
- S3 Bucket Policy : accès conditionnel via CloudFront SourceArn
