# Secure Cloud Infrastructure — Threat Model

## 1. Purpose and Scope

This threat model evaluates the security of the Secure Cloud Infrastructure Lab, a multi-tier AWS environment provisioned with Terraform.

The environment is designed around defense in depth, network segmentation, least-privilege access, private service connectivity, centralized logging, and automated security validation.

The primary application path is:

```text
Internet → HTTPS ALB → Private EC2 → Private PostgreSQL RDS
```

The EC2 application tier also communicates with required AWS services through VPC endpoints rather than relying on general Internet access.

GitHub Actions performs infrastructure and security validation, while AWS access for the runtime security scanner uses OpenID Connect (OIDC) and short-lived AWS credentials.

This threat model focuses on attacks against the cloud architecture and its supporting CI/CD and identity infrastructure.

---

## 2. Security-Relevant Architecture

The environment contains three primary network tiers:

* Public subnets contain the Internet-facing Application Load Balancer.
* Private application subnets contain the EC2 application workload.
* Private data subnets contain the PostgreSQL RDS database.

Security groups restrict communication between these tiers.

The intended application flow is:

```text
Internet
   |
   | HTTPS TCP/443
   v
Application Load Balancer
   |
   | HTTP TCP/8080
   v
Private EC2 Application
   |
   | PostgreSQL TCP/5432
   v
Private RDS
```

The application instance does not normally have a default route to the Internet.

Required AWS services are instead accessed through purpose-specific VPC endpoints, including S3, Systems Manager, Systems Manager Messages, and Secrets Manager.

Administrative access to EC2 uses AWS Systems Manager Session Manager rather than inbound SSH.

CloudTrail records AWS API activity, while VPC Flow Logs provide network traffic metadata.

---

## 3. Assets

Important assets include:

* Application and customer traffic
* EC2 application workload
* PostgreSQL database and application data
* Database credentials
* S3 application data
* AWS IAM identities and temporary credentials
* Terraform infrastructure configuration
* GitHub repository and CI/CD configuration
* CloudTrail audit records
* VPC Flow Log records

Compromise of the EC2 application tier is particularly significant because the instance occupies a trusted position between the public application entry point and private resources.

---

## 4. Trust Boundaries

### Internet → Application Load Balancer

The Internet is considered untrusted.

The ALB provides the public application entry point and accepts HTTPS traffic on TCP/443.

### Application Load Balancer → EC2

Only the ALB security group is authorized to initiate application traffic to EC2 on TCP/8080.

The EC2 instance has no public IPv4 address.

### EC2 → RDS

Only the application security group is authorized to initiate PostgreSQL connections to the database security group on TCP/5432.

Database authentication is still required after network access is established.

### EC2 → AWS Services

The application communicates with selected AWS services through VPC endpoints.

Network connectivity to an AWS service does not itself grant access. IAM authorization independently determines which API operations the EC2 role may perform.

### GitHub Actions → AWS

GitHub Actions authenticates to AWS using OIDC.

AWS validates the GitHub identity against the IAM role trust policy before AWS STS issues short-lived credentials.

Long-lived AWS access keys are not stored in the GitHub repository for this integration.

---

## 5. Threat Modeling Methodology

Threats are categorized using STRIDE:

* **Spoofing** — impersonating another identity or system
* **Tampering** — unauthorized modification of data or infrastructure
* **Repudiation** — performing an action without sufficient evidence for attribution
* **Information Disclosure** — unauthorized exposure of information
* **Denial of Service** — reducing or eliminating system availability
* **Elevation of Privilege** — gaining permissions beyond those originally authorized

Threats are also evaluated using qualitative likelihood and impact.

The final risk rating represents residual risk after existing security controls are considered.

---

## 6. Threat Register

| #  | Threat                                         | STRIDE                                                      | Likelihood | Impact   | Residual Risk | Treatment                       |
| -- | ---------------------------------------------- | ----------------------------------------------------------- | ---------- | -------- | ------------- | ------------------------------- |
| 1  | Direct Internet access to RDS                  | Information Disclosure / Tampering                          | Low        | High     | Low           | Mitigate                        |
| 2  | EC2 application compromise                     | Elevation of Privilege / Information Disclosure / Tampering | Medium     | High     | High          | Mitigate / Accept residual risk |
| 3  | Database credential theft                      | Information Disclosure / Spoofing                           | Medium     | High     | High          | Mitigate / Accept residual risk |
| 4  | AWS privilege escalation from EC2              | Elevation of Privilege                                      | Low        | Critical | Medium        | Mitigate                        |
| 5  | Malicious infrastructure change through GitHub | Tampering / Elevation of Privilege                          | Low        | High     | Medium        | Mitigate                        |
| 6  | AWS infrastructure modified outside Terraform  | Tampering / Repudiation                                     | Medium     | Medium   | Medium        | Detect / Mitigate               |
| 7  | Audit evidence disabled or manipulated         | Tampering / Repudiation                                     | Low        | High     | Medium        | Mitigate                        |
| 8  | Data exfiltration from compromised EC2         | Information Disclosure                                      | Low–Medium | High     | Medium        | Mitigate                        |
| 9  | Application DoS or infrastructure failure      | Denial of Service                                           | Medium     | Medium   | Medium        | Accept                          |
| 10 | Application traffic interception               | Information Disclosure / Tampering                          | Low        | Medium   | Low           | Mitigate / Accept residual risk |

### T1 — Direct Internet Access to RDS

**Threat:** An external attacker attempts to connect directly to the PostgreSQL database.

**Existing controls:**

* RDS is not publicly accessible.
* RDS resides in private data subnets.
* The database security group permits TCP/5432 from the application security group rather than arbitrary Internet addresses.
* Database authentication is required.

**Residual risk:** A compromised application workload already occupies a network position authorized to communicate with RDS.

**Treatment:** Mitigated.

---

### T2 — EC2 Application Compromise

**Threat:** An attacker exploits the application and obtains code execution on the EC2 instance.

**Attack path:**

```text
Internet
   ↓
ALB
   ↓
Application vulnerability
   ↓
EC2 code execution
   ↓
AWS role / Secrets Manager / RDS / S3
```

**Existing controls:**

* EC2 has no public IPv4 address.
* Application ingress is restricted to the ALB security group.
* Inbound SSH is not required.
* IMDSv2 is required.
* The EC2 IAM role is limited to required permissions.
* Security-group egress is restricted.
* General Internet access is unavailable during normal operation.
* Required AWS services are reached through VPC endpoints.
* CloudTrail and VPC Flow Logs provide investigative evidence.

**Residual risk:** A sufficiently compromised application instance may exercise permissions legitimately granted to the workload.

**Treatment:** Mitigated with residual risk accepted.

---

### T3 — Database Credential Theft

**Threat:** An attacker retrieves database credentials after compromising an authorized workload.

**Attack path:**

```text
Compromised EC2
      ↓
EC2 IAM role
      ↓
Secrets Manager GetSecretValue
      ↓
RDS credential
      ↓
Database access
```

**Existing controls:**

* RDS manages the master credential through Secrets Manager.
* Database credentials are not committed to Git.
* The password is not directly stored in Terraform configuration.
* Secret retrieval requires IAM authorization.
* RDS is private.
* PostgreSQL connections require TLS.

**Residual risk:** Because the application legitimately requires the database credential, compromise of the authorized workload may result in credential retrieval.

Secrets Manager protects credential storage and distribution but cannot prevent an authorized workload from exercising its legitimate permissions after that workload is compromised.

**Treatment:** Mitigated with residual risk accepted.

---

### T4 — AWS Privilege Escalation from EC2

**Threat:** An attacker uses the EC2 instance role to obtain broader AWS privileges.

**Existing controls:**

* The instance uses a limited IAM role rather than administrative permissions.
* Long-lived AWS credentials are not embedded on the instance.
* Role credentials are temporary.
* IMDSv2 is required.
* CloudTrail records AWS API activity.

**Residual risk:** An attacker controlling the instance inherits the permissions legitimately granted to its IAM role. Future IAM policy mistakes could increase this blast radius.

**Treatment:** Mitigated.

---

### T5 — Malicious Infrastructure Change Through GitHub

**Threat:** An attacker gains sufficient GitHub access and introduces insecure Terraform or CI/CD configuration.

An example would be modifying the application security group to permit public SSH access.

**Existing controls:**

* Git provides infrastructure change history.
* GitHub Actions validates Terraform formatting and configuration.
* Checkov performs static security analysis of Terraform.
* Python scanner logic has automated unit tests.
* AWS authentication uses OIDC rather than stored long-lived AWS credentials.
* The GitHub security-scanning AWS role is read-only.

**Residual risk:** A sufficiently privileged repository attacker may attempt to alter workflows, infrastructure configuration, or security checks. Repository access controls and protected-branch policies remain important.

**Treatment:** Mitigated.

---

### T6 — Infrastructure Modified Outside Terraform

**Threat:** An authorized or compromised AWS identity modifies infrastructure directly through the AWS API or Console, causing the deployed environment to differ from the Terraform configuration.

**Existing controls:**

* Terraform defines the intended infrastructure state.
* Terraform planning can identify infrastructure drift.
* CloudTrail records AWS API activity and identity information.
* Normal project practice uses the AWS Console primarily for inspection rather than infrastructure modification.

**Residual risk:** Terraform does not continuously prevent identities with sufficient AWS permissions from making direct AWS changes.

**Treatment:** Detect and mitigate.

---

### T7 — Audit Evidence Disabled or Manipulated

**Threat:** An attacker attempts to disable or modify logging to conceal malicious activity.

**Existing controls:**

* Multi-region CloudTrail
* CloudTrail log-file validation
* S3 audit-log storage
* CloudTrail integration with CloudWatch Logs
* VPC Flow Logs
* IAM-controlled logging infrastructure

**Residual risk:** The lab does not use a separate organizational security account or fully immutable cross-account logging architecture. A sufficiently privileged account-level attacker could potentially interfere with logging infrastructure.

**Treatment:** Mitigated. Cross-account centralized logging is outside the scope of the lab.

---

### T8 — Data Exfiltration from Compromised EC2

**Threat:** An attacker controlling EC2 attempts to send stolen application data to an external attacker-controlled system.

**Existing controls:**

* Application subnets do not normally have a default Internet route.
* No NAT Gateway is required during normal operation.
* Security-group egress is restricted.
* AWS service access uses purpose-specific VPC endpoints.
* IAM restricts access to AWS resources.

**Residual risk:** Restricted Internet egress significantly reduces straightforward command-and-control and data-exfiltration paths but cannot guarantee that exfiltration is impossible. An attacker may attempt to abuse an authorized service or application communication path.

**Treatment:** Mitigated.

---

### T9 — Application DoS or Infrastructure Failure

**Threat:** Malicious traffic or infrastructure failure causes application unavailability.

**Existing controls:**

* The Internet-facing ALB spans two Availability Zones.
* ALB target health checks are configured.
* Network tiers span multiple Availability Zones.

**Residual risk:**

The lab intentionally uses:

* One EC2 application instance
* Single-AZ RDS
* No application Auto Scaling
* No AWS WAF deployment

The architecture therefore does not provide production-grade application or database availability.

**Treatment:** Accepted lab risk due to cost and project scope.

Production improvements could include multiple application instances, Auto Scaling, Multi-AZ RDS, WAF, enhanced monitoring, and additional availability controls.

---

### T10 — Application Traffic Interception

**Threat:** Application traffic is intercepted or manipulated in transit.

**Existing controls:**

* Clients communicate with the ALB using HTTPS.
* The ALB uses a modern TLS security policy.
* Security groups tightly restrict ALB-to-EC2 communication.

**Residual risk:** TLS terminates at the ALB, while ALB-to-EC2 application traffic uses HTTP on TCP/8080. The lab also uses a self-signed certificate rather than a publicly trusted production certificate.

**Treatment:** Internet-facing traffic risk is mitigated. Backend encryption and publicly trusted certificate deployment are accepted lab limitations.

---

## 7. Primary Attack Path

The most significant attack chain identified by this threat model is compromise of the Internet-facing application followed by abuse of the application's legitimate trust relationships.

```text
Internet attacker
       ↓
HTTPS ALB
       ↓
Application vulnerability
       ↓
Compromised EC2
       ↓
EC2 IAM role
       ↓
Secrets Manager
       ↓
Database credential
       ↓
Private RDS
       ↓
Application data
```

The database being private does not prevent this attack because the compromised application server is intentionally authorized to communicate with the database.

The architecture therefore relies on defense in depth to reduce the attacker's blast radius.

Network segmentation limits lateral movement. Least-privilege IAM limits AWS API access. Restricted egress reduces straightforward external command-and-control and exfiltration. CloudTrail and VPC Flow Logs provide evidence for investigation.

This demonstrates an assume-breach design principle: the architecture does not rely on every internal component remaining trustworthy indefinitely.

---

## 8. Accepted Risks and Scope Limitations

The following risks are consciously accepted for the lab:

* Single EC2 application instance
* Single-AZ RDS deployment
* No AWS WAF
* No application Auto Scaling
* Self-signed TLS certificate
* HTTP communication between the ALB and EC2 backend
* No centralized cross-account security logging
* AWS-managed encryption or SSE-S3 in areas where customer-managed KMS keys were considered outside project scope
* Limited log-retention periods for cost control

These decisions represent cost, complexity, and scope tradeoffs rather than assumptions that the associated risks do not exist.

A production deployment would reevaluate each decision according to business requirements, data sensitivity, availability requirements, regulatory requirements, and threat environment.

---

## 9. Security Conclusions

The architecture uses defense in depth rather than relying on a single preventive control.

The primary security principles demonstrated by the environment are:

* Minimize direct Internet exposure.
* Segment public, application, and data workloads.
* Explicitly authorize workload-to-workload network paths.
* Apply least-privilege IAM permissions.
* Prefer temporary AWS credentials over long-lived credentials.
* Keep secrets outside source code and Terraform configuration.
* Restrict unnecessary outbound Internet connectivity.
* Use private AWS service connectivity where appropriate.
* Record control-plane activity with CloudTrail.
* Record network traffic metadata with VPC Flow Logs.
* Validate infrastructure before deployment using Terraform and Checkov.
* Independently inspect deployed AWS configuration using a Boto3 security scanner.
* Assume individual workloads may eventually be compromised and design to contain the resulting blast radius.

The highest residual risks are associated with compromise of the application tier and subsequent abuse of permissions that the application legitimately requires.

The goal of the architecture is therefore not to claim that compromise is impossible, but to reduce attack surface, constrain attacker movement, protect high-value assets, preserve investigative evidence, and make remaining risks explicit.
