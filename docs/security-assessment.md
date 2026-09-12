# Secure Cloud Infrastructure — Security Assessment

## 1. Executive Summary

This assessment evaluates the security posture of the Secure Cloud Infrastructure Lab, a Terraform-managed AWS environment designed to demonstrate cloud security engineering practices.

The environment implements defense-in-depth controls across networking, identity, compute, storage, database security, logging, secrets management, CI/CD, and automated security validation.

The assessment identified no known critical findings in the project-managed infrastructure.

The strongest controls include:

* Private EC2 and RDS workloads
* Security-group-based network segmentation
* No inbound SSH
* Restricted application-tier Internet egress
* VPC endpoints for required AWS services
* Least-privilege IAM
* IMDSv2 enforcement
* Centralized CloudTrail and VPC Flow Log visibility
* Secrets Manager integration
* Terraform and Checkov validation
* Account-wide Boto3 security auditing
* GitHub Actions authentication through OIDC rather than long-lived AWS keys

The most significant residual risk is application-tier compromise. The EC2 workload is legitimately authorized to retrieve the RDS-managed master credential and communicate with the database. Therefore, successful compromise of the application host could provide an attacker with highly privileged database access.

Several additional findings involve availability, encryption scope, TLS architecture, logging architecture, and lab-specific cost decisions.

Overall, the environment demonstrates a strong security posture for a learning lab while intentionally accepting several controls that would require additional hardening before production deployment.

---

## 2. Scope

The assessment covers the AWS infrastructure and supporting security tooling implemented by this project, including:

* VPC networking
* Public, application, and data subnets
* Route tables and Internet connectivity
* Security groups
* Application Load Balancer
* EC2
* RDS PostgreSQL
* S3
* Secrets Manager
* VPC endpoints
* IAM
* CloudTrail
* VPC Flow Logs
* CloudWatch Logs
* Terraform
* Checkov
* Python/Boto3 security scanner
* GitHub Actions and AWS OIDC authentication

This assessment is not a penetration test and does not evaluate the security of a production application codebase.

---

## 3. Assessment Methodology

The assessment combines several approaches.

### Architecture Review

Network paths, trust boundaries, IAM relationships, Internet exposure, service connectivity, and security controls were reviewed against the intended architecture.

### Threat Modeling

STRIDE-based threat modeling was used to identify attack paths involving:

* Application compromise
* Credential theft
* Database access
* AWS privilege escalation
* Infrastructure tampering
* Audit-log interference
* Data exfiltration
* Denial of service

### Infrastructure-as-Code Analysis

Terraform configuration was evaluated with Checkov.

Findings were either remediated or explicitly documented when a production-oriented control was intentionally outside the scope of the lab.

### Live AWS Configuration Auditing

A custom Python/Boto3 scanner evaluates deployed AWS configuration independently of Terraform.

This provides detective coverage for resources that may exist outside the project's Terraform state.

### Manual Security Validation

Selected controls were validated through controlled testing, including:

* Private EC2 administration through Systems Manager
* VPC endpoint connectivity
* Restricted Internet egress
* Secrets Manager access
* S3 authorization behavior
* PostgreSQL connectivity
* CloudTrail investigation
* VPC Flow Log investigation
* GitHub OIDC authentication

---

## 4. Severity Definitions

| Severity      | Meaning                                                                              |
| ------------- | ------------------------------------------------------------------------------------ |
| Critical      | Immediate compromise or broad administrative control is likely or directly exposed   |
| High          | Exploitation could significantly compromise sensitive systems or data                |
| Medium        | Meaningful security weakness requiring additional conditions or having limited scope |
| Low           | Limited-impact weakness, defense-in-depth improvement, or low-likelihood scenario    |
| Informational | Security observation or operational improvement with minimal direct security impact  |

Ratings represent the residual risk remaining after existing controls are considered.

---

## 5. Positive Security Controls

The assessment identified several areas where the environment significantly reduces attack surface.

### Network Segmentation

The environment separates public, application, and data resources.

Only the Application Load Balancer is intentionally Internet-facing.

EC2 and RDS remain private.

### Workload-Based Security Groups

Security-group references establish explicit relationships:

```text
Internet → ALB :443
ALB SG → Application SG :8080
Application SG → Database SG :5432
```

This avoids treating the entire VPC as trusted.

### No Direct SSH Administration

EC2 does not require inbound TCP/22.

Systems Manager Session Manager provides administrative access through AWS-controlled authentication and private VPC connectivity.

### Restricted Internet Egress

The application tier normally has no NAT Gateway or general Internet default route.

Required AWS services are accessed through VPC endpoints.

This reduces common malware download, command-and-control, and direct exfiltration paths after workload compromise.

### Least-Privilege IAM

EC2 receives temporary role credentials and does not receive broad AWS administrative permissions.

The GitHub live security scanner similarly uses a read-only AWS role.

### Temporary CI Credentials

GitHub Actions authenticates using OIDC and AWS STS.

No long-lived AWS access key is required for the GitHub-to-AWS integration.

### Security Visibility

CloudTrail records AWS control-plane activity.

VPC Flow Logs provide network metadata.

Together, these support investigation across different layers of the environment.

### Independent Security Validation

Checkov evaluates intended Terraform configuration, while the Boto3 scanner evaluates actual AWS account state.

This provides both preventive and detective validation.

---

## 6. Security Findings

### SEC-01 — Application Access to RDS Master Credential

**Severity:** High

**Affected components:** EC2, IAM, Secrets Manager, RDS

#### Observation

The EC2 application role is authorized to retrieve the RDS-managed master credential from Secrets Manager.

The credential is securely stored outside Terraform and Git, but the application receives access to a highly privileged database identity.

#### Security Impact

Successful compromise of the application instance could allow an attacker to:

```text
Compromise EC2
      ↓
Use EC2 IAM role
      ↓
Retrieve RDS master secret
      ↓
Authenticate to PostgreSQL
      ↓
Exercise master-user database privileges
```

Network segmentation does not prevent this attack because the EC2 application is intentionally authorized to communicate with RDS.

#### Existing Controls

* RDS is private.
* Database SG permits access only from the application SG.
* Secrets Manager stores the credential.
* Secret access requires IAM authorization.
* PostgreSQL TLS is enforced.
* CloudTrail provides AWS API evidence.
* PostgreSQL logging provides database-level evidence.

#### Recommendation

Create a dedicated application database identity with only the permissions required by the application.

The RDS master credential should be reserved for database administration.

For example, the application identity could receive access only to required schemas, tables, and SQL operations.

#### Disposition

Recommended production improvement.

This is the highest-priority residual security finding identified by the assessment.

---

### SEC-02 — Single EC2 Application Instance

**Severity:** Medium

**Affected component:** EC2

#### Observation

The network architecture spans two Availability Zones, but only one EC2 application instance is deployed.

#### Security Impact

Failure or compromise of the instance can make the application unavailable.

The multi-AZ ALB does not provide application-tier redundancy when only one backend target exists.

#### Existing Controls

* Multi-AZ ALB
* ALB health checks
* Multi-AZ subnet architecture

#### Recommendation

For production, deploy multiple application instances through an Auto Scaling Group across multiple Availability Zones.

#### Disposition

Accepted lab risk due to cost and scope.

---

### SEC-03 — Single-AZ RDS Deployment

**Severity:** Medium

**Affected component:** RDS

#### Observation

The RDS subnet group spans two Availability Zones, but the database itself uses a Single-AZ deployment.

#### Security Impact

An Availability Zone failure or database infrastructure failure may cause database and application unavailability.

#### Existing Controls

* Automated backups
* Multi-AZ-capable subnet design
* Encrypted database storage

#### Recommendation

Enable Multi-AZ RDS for a production workload with meaningful availability requirements.

#### Disposition

Accepted lab risk due to cost and scope.

---

### SEC-04 — Unencrypted ALB-to-EC2 Application Traffic

**Severity:** Medium

**Affected components:** ALB, EC2

#### Observation

Client traffic uses HTTPS to the ALB, but TLS terminates at the load balancer.

The ALB communicates with the EC2 application using HTTP on TCP/8080.

#### Security Impact

An attacker with sufficient access to the internal network path could potentially observe or manipulate backend application traffic.

#### Existing Controls

* EC2 is private.
* Backend traffic is restricted by security-group references.
* Only the ALB SG is authorized to initiate TCP/8080 traffic to the application.

#### Recommendation

For production environments requiring end-to-end encryption, configure HTTPS between the ALB and backend application targets.

#### Disposition

Accepted lab risk.

---

### SEC-05 — No Web Application Firewall

**Severity:** Medium

**Affected component:** Internet-facing ALB

#### Observation

AWS WAF is not deployed in front of the Internet-facing application.

#### Security Impact

The environment lacks an additional managed filtering layer for common web attack patterns and abusive traffic.

WAF would not eliminate application vulnerabilities but could provide additional defense in depth.

#### Existing Controls

* HTTPS-only Internet entry point
* ALB security-group restrictions
* Private application host
* Network segmentation

#### Recommendation

Evaluate AWS WAF for a production Internet-facing application and configure rules appropriate to the application's threat model.

#### Disposition

Accepted lab risk due to cost and project scope.

---

### SEC-06 — Self-Signed TLS Certificate

**Severity:** Low

**Affected component:** ALB / ACM

#### Observation

The lab uses a self-signed TLS certificate imported into AWS Certificate Manager.

#### Security Impact

The certificate does not provide the public trust chain expected for a production Internet service.

Clients cannot automatically establish the same level of certificate trust they would receive from a publicly trusted certificate authority.

#### Existing Controls

* TLS is enabled.
* A modern ALB TLS policy is configured.
* The certificate demonstrates TLS termination and certificate management.

#### Recommendation

Use a publicly trusted ACM certificate associated with a controlled DNS domain for production.

#### Disposition

Accepted lab limitation.

---

### SEC-07 — Audit Logs Are Not Isolated in a Separate Security Account

**Severity:** Low

**Affected components:** CloudTrail, S3, CloudWatch

#### Observation

Audit evidence remains within the same AWS account as the workloads being monitored.

#### Security Impact

An attacker who obtains sufficiently powerful account permissions may be able to interfere with both production resources and security evidence.

#### Existing Controls

* Multi-region CloudTrail
* CloudTrail log-file validation
* S3 audit archive
* S3 versioning
* CloudWatch integration
* IAM restrictions
* VPC Flow Logs

#### Recommendation

For a mature production environment, centralize security logs in a dedicated security or logging account with tightly restricted modification and deletion permissions.

#### Disposition

Future production improvement.

Cross-account centralized logging is outside the scope of the lab.

---

### SEC-08 — Customer-Managed KMS Keys Not Used for All Data

**Severity:** Low

**Affected components:** Selected S3, logging, and secrets resources

#### Observation

The project uses AWS-managed encryption or SSE-S3 for some resources instead of dedicated customer-managed KMS keys.

#### Security Impact

Data remains encrypted at rest, but the architecture lacks some of the key-policy control, separation of duties, and lifecycle control available with customer-managed KMS keys.

#### Existing Controls

* Encryption at rest is enabled.
* S3 public access is blocked.
* IAM controls access to encrypted resources.

#### Recommendation

Evaluate customer-managed KMS keys where regulatory requirements, key-policy isolation, auditing requirements, or separation of duties justify the additional complexity and cost.

#### Disposition

Accepted lab scope decision.

---

### SEC-09 — Default VPC Does Not Have VPC Flow Logs

**Severity:** Low

**Affected component:** AWS account default VPC

#### Observation

The account-wide Boto3 scanner identifies that the AWS default VPC does not have VPC Flow Logs enabled.

The Terraform-managed project VPC does have Flow Logs enabled.

#### Security Impact

If resources were deployed into the default VPC, network-level investigative visibility would be weaker than in the project-managed VPC.

#### Existing Controls

The application architecture does not use the default VPC.

The custom project VPC has VPC Flow Logs enabled.

#### Recommendation

Either enable Flow Logs for the default VPC or remove unused default networking resources according to organizational policy.

#### Disposition

Low-severity account-hygiene finding.

The scanner intentionally retains this finding because it audits the AWS account rather than only resources created by this Terraform project.

---

### SEC-10 — Limited CloudWatch Log Retention

**Severity:** Informational

**Affected components:** CloudWatch Logs

#### Observation

CloudTrail and VPC Flow Log CloudWatch groups use limited retention periods appropriate to the lab.

#### Security Impact

Older CloudWatch records eventually become unavailable for interactive investigation.

This may limit historical investigations requiring data outside the retention window.

#### Existing Controls

CloudTrail additionally delivers logs to a durable S3 audit bucket.

#### Recommendation

Production retention should be determined by incident-response requirements, organizational policy, compliance obligations, and storage cost.

#### Disposition

Accepted lab cost decision.

---

## 7. Prioritized Recommendations

### Priority 1 — Reduce Database Privilege

Replace application use of the RDS master credential with a dedicated least-privilege database identity.

This provides the greatest reduction in the impact of application compromise.

### Priority 2 — Improve Application Availability

Deploy multiple EC2 application instances across Availability Zones using an Auto Scaling Group.

### Priority 3 — Improve Database Availability

Enable Multi-AZ RDS for workloads with production availability requirements.

### Priority 4 — Add Application-Layer Protection

Evaluate AWS WAF and application-specific security controls for the Internet-facing entry point.

### Priority 5 — Extend Encryption in Transit

Use TLS between the ALB and backend application where end-to-end encryption is required.

### Priority 6 — Strengthen Audit Isolation

Centralize security logs in a dedicated AWS account for production environments with stronger evidence-preservation requirements.

---

## 8. Defense-in-Depth Evaluation

No single security control is responsible for protecting the environment.

For example, consider application compromise.

```text
Internet
   ↓
ALB
   ↓
Application vulnerability
   ↓
EC2 compromise
```

At this point, the architecture does not assume that the attack has been completely prevented.

Instead, additional controls continue to operate:

```text
EC2 compromised
      |
      +→ No AWS administrator IAM permissions
      |
      +→ Restricted security-group paths
      |
      +→ No normal general Internet route
      |
      +→ Only authorized AWS service access
      |
      +→ CloudTrail records AWS API activity
      |
      +→ Flow Logs provide network metadata
```

The remaining database-credential risk demonstrates why defense in depth must continue beyond AWS networking and IAM into application and database authorization.

---

## 9. Automated Validation vs. Manual Analysis

The project demonstrates why multiple assessment techniques are required.

### Checkov

Checkov evaluates Terraform configuration before deployment.

It is effective for identifying known infrastructure configuration weaknesses.

### Boto3 Security Scanner

The custom scanner evaluates live AWS account state.

It can identify configuration outside the Terraform project, including the default VPC Flow Log finding.

### Threat Modeling

Threat modeling identifies attack chains that may not correspond directly to a configuration rule.

### Manual Security Assessment

Manual analysis provides context that automated tools cannot fully understand.

For example:

```text
Secrets Manager enabled
        ↓
Automated check: GOOD

Application retrieves RDS master credential
        ↓
Manual analysis: HIGH residual impact after app compromise
```

Passing automated security checks therefore does not mean that an architecture has no meaningful security risk.

---

## 10. Overall Security Posture

The Secure Cloud Infrastructure Lab demonstrates a strong security posture relative to its educational scope.

The architecture significantly reduces direct Internet exposure and applies meaningful controls across networking, identity, secrets, storage, compute, databases, logging, and CI/CD.

Particularly strong design decisions include:

* Exposing only the ALB to the Internet
* Keeping EC2 and RDS private
* Eliminating inbound SSH
* Restricting application-tier Internet egress
* Using security-group references between tiers
* Separating network connectivity from IAM authorization
* Using VPC endpoints for required AWS services
* Using temporary AWS credentials
* Authenticating GitHub through OIDC
* Combining CloudTrail and Flow Logs
* Combining static IaC analysis with live account auditing

The environment still contains legitimate residual risk.

The highest-priority issue is the application's access to the RDS master credential because application compromise could translate into highly privileged database access.

Other findings primarily represent production hardening and availability controls deliberately excluded from the lab due to cost and scope.

The project therefore demonstrates not only implementation of security controls but also the ability to identify weaknesses, prioritize risk, distinguish remediation from risk acceptance, and explain where automated security tools stop being sufficient.
