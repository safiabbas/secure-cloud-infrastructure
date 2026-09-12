# Secure Cloud Infrastructure Lab

A security-focused AWS infrastructure project built with Terraform and Python. The lab demonstrates how network segmentation, private workloads, least-privilege IAM, restricted egress, centralized logging, and automated security validation work together in a realistic multi-tier cloud environment.

![Secure Cloud Infrastructure Architecture](diagrams/secure-cloud-architecture.png)

## Architecture

The primary application path is:

```text
Internet → HTTPS Application Load Balancer → Private EC2 → Private PostgreSQL RDS
```

The VPC spans two Availability Zones and separates resources into public, application, and data tiers. Only the ALB is intentionally Internet-facing. EC2 and RDS remain private.

The application tier normally has no NAT Gateway or general Internet default route. Required AWS services are reached through private VPC connectivity:

- S3 through a gateway endpoint
- Systems Manager through interface endpoints
- Systems Manager Messages through interface endpoints
- Secrets Manager through an interface endpoint

Administrative access uses AWS Systems Manager Session Manager instead of inbound SSH.

## Security Controls

### Network Security

- Six-subnet, two-AZ VPC design with separate public, application, and data tiers
- Internet-facing ALB as the only public application entry point
- Private EC2 instance with no public IPv4 address
- Private RDS instance with `publicly_accessible = false`
- Security-group references between tiers instead of broad VPC CIDR trust
- Restricted application egress with no normal general-purpose Internet route
- Explicitly restricted default VPC security group

### Identity and Secrets

- EC2 instance role with temporary AWS credentials
- IMDSv2 required on EC2
- AWS Systems Manager for administration instead of SSH
- RDS-managed master credential stored in Secrets Manager
- GitHub Actions authenticates to AWS with OIDC and STS rather than long-lived access keys
- GitHub live-security-scan role is read-only

### Data Protection

- Encrypted EC2 root volume
- Encrypted RDS storage
- S3 Block Public Access
- S3 server-side encryption and versioning
- Bucket policies deny insecure transport
- PostgreSQL TLS enforcement

### Logging and Visibility

- Multi-region CloudTrail with log-file validation
- CloudTrail delivery to CloudWatch Logs and S3
- VPC Flow Logs for network metadata
- PostgreSQL connection, disconnection, and slow-query logging

## Automated Security Validation

The project uses two complementary forms of security validation.

### Checkov

Checkov statically analyzes the Terraform configuration before deployment. Production-oriented checks that are intentionally outside the lab's cost or scope are documented with explicit suppression reasons rather than silently ignored.

### Python / Boto3 Security Scanner

`scripts/security_scanner.py` queries live AWS configuration independently of Terraform state. It evaluates controls including:

- S3 public-access blocking, versioning, and encryption
- EC2 public IPv4 exposure, IMDSv2, and root-volume encryption
- Public security-group exposure on sensitive ports
- Private-subnet default routes and public-IP assignment
- CloudTrail status and hardening
- VPC Flow Logs
- Required VPC endpoints
- Secrets Manager status

Findings use severity weights to produce a security score and are written to `security_report.json`. The scanner exits non-zero when failures are present so it can be used as a detective security control rather than merely producing informational output.

The live scanner intentionally examines AWS account state rather than trusting Terraform alone, which allows it to surface configuration outside the project's managed resources.

## CI/CD Security

GitHub Actions runs automated validation on pushes and pull requests:

```text
Terraform fmt check
        ↓
Terraform validate
        ↓
Checkov IaC scan
        ↓
Python syntax validation
        ↓
Unit tests
```

A separate manually triggered workflow obtains short-lived AWS credentials through GitHub OIDC and runs the live Boto3 security scanner with a read-only IAM role.

Terraform is not automatically applied by CI.

## Security Analysis

The repository includes security documentation beyond infrastructure code:

- [`docs/architecture.md`](docs/architecture.md) — architecture and security design decisions
- [`docs/threat-model.md`](docs/threat-model.md) — STRIDE-based threat model and attack-path analysis
- [`docs/security-assessment.md`](docs/security-assessment.md) — findings, residual risk, risk acceptance, and prioritized recommendations

The highest-priority residual risk identified by the assessment is application access to the RDS master credential. Secrets Manager protects credential storage and distribution, but a compromised application host that is legitimately authorized to retrieve the master credential could still gain highly privileged database access. A production design would use a dedicated least-privilege database identity for the application.

## Repository Structure

```text
.
├── .github/workflows/
│   └── terraform-ci.yml
├── diagrams/
│   ├── secure-cloud-architecture.drawio
│   ├── secure-cloud-architecture.png
│   └── secure-cloud-architecture.svg
├── docs/
│   ├── architecture.md
│   ├── security-assessment.md
│   └── threat-model.md
├── scripts/
│   └── security_scanner.py
├── terraform/
│   ├── compute.tf
│   ├── database.tf
│   ├── endpoints.tf
│   ├── iam.tf
│   ├── load_balancer.tf
│   ├── logging.tf
│   ├── networking.tf
│   ├── security_groups.tf
│   ├── storage.tf
│   └── ...
├── tests/
│   └── test_security_scanner.py
└── README.md
```

## Local Validation

From the repository root, the Python tests can be run with:

```powershell
python -m unittest discover -s tests -v
```

Terraform validation can be run from the `terraform` directory:

```powershell
terraform fmt -check -recursive; terraform init -backend=false; terraform validate
```

The live scanner can be run with an authenticated AWS CLI profile:

```powershell
$env:AWS_PROFILE="secure-cloud"; python scripts/security_scanner.py
```

The scanner is expected to return a non-zero exit code whenever it finds a failed control.

## Runtime and Cost Model

Cost-incurring runtime resources are controlled with the `enable_runtime_resources` Terraform variable and are disabled by default. This allows the project to retain its Infrastructure-as-Code design while avoiding unnecessary ongoing lab charges.

When enabled, the runtime layer includes the ALB, private EC2 instance, private RDS instance, and interface VPC endpoints.

## Deliberate Lab Tradeoffs

This project is a security engineering lab, not a production reference architecture. The following limitations are intentionally documented rather than hidden:

- One EC2 application instance rather than an Auto Scaling Group
- Single-AZ RDS
- No AWS WAF
- Self-signed lab TLS certificate
- HTTP from the ALB to EC2 after TLS termination
- No dedicated cross-account immutable logging account
- AWS-managed or SSE-S3 encryption for selected resources instead of customer-managed KMS keys
- Shorter CloudWatch retention periods for cost control

See the [security assessment](docs/security-assessment.md) for the associated risk analysis and recommendations.

## Technologies

AWS, Terraform, Python, Boto3, IAM, VPC, EC2, ALB, RDS PostgreSQL, S3, Secrets Manager, Systems Manager, VPC Endpoints, CloudTrail, VPC Flow Logs, CloudWatch, GitHub Actions, OpenID Connect, Checkov
