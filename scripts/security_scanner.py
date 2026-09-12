import boto3
import sys
import json
from datetime import datetime, timezone
import os

profile_name = os.getenv("AWS_PROFILE")

if profile_name:
    session = boto3.Session(profile_name=profile_name)
else:
    session = boto3.Session()

sts = session.client("sts")
s3 = session.client("s3")
ec2 = session.client("ec2")
cloudtrail = session.client("cloudtrail")
secretsmanager = session.client("secretsmanager")

SENSITIVE_PORTS = {
    22: "SSH",
    3389: "RDP",
    3306: "MySQL",
    5432: "PostgreSQL",
    8080: "Application",
}

REQUIRED_VPC_ENDPOINT_SERVICES = {
    "com.amazonaws.us-east-1.s3",
    "com.amazonaws.us-east-1.ssm",
    "com.amazonaws.us-east-1.ssmmessages",
    "com.amazonaws.us-east-1.secretsmanager",
}

SEVERITY_WEIGHTS = {
    "HIGH": 10,
    "MEDIUM": 5,
    "LOW": 2,
}

def create_finding(check_id, status, severity, resource, message):
    return {
        "check_id": check_id,
        "status": status,
        "severity": severity,
        "resource": resource,
        "message": message,
    }

def check_s3_public_access():
    findings = []

    response = s3.list_buckets()

    for bucket in response["Buckets"]:
        bucket_name = bucket["Name"]

        try:
            public_access = s3.get_public_access_block(Bucket=bucket_name)
            config = public_access["PublicAccessBlockConfiguration"]

            all_blocked = (
                config["BlockPublicAcls"]
                and config["IgnorePublicAcls"]
                and config["BlockPublicPolicy"]
                and config["RestrictPublicBuckets"]
            )

            if all_blocked:
                finding = create_finding(
                    "S3_PUBLIC_ACCESS",
                    "PASS",
                    "HIGH",
                    bucket_name,
                    "All S3 Block Public Access controls are enabled",
                )
            else:
                finding = create_finding(
                    "S3_PUBLIC_ACCESS",
                    "FAIL",
                    "HIGH",
                    bucket_name,
                    "One or more S3 Block Public Access controls are disabled",
                )

        except s3.exceptions.NoSuchPublicAccessBlockConfiguration:
            finding = create_finding(
                "S3_PUBLIC_ACCESS",
                "FAIL",
                "HIGH",
                bucket_name,
                "Bucket has no Block Public Access configuration",
            )

        findings.append(finding)

    return findings

def check_s3_versioning():
    findings = []

    response = s3.list_buckets()

    for bucket in response["Buckets"]:
        bucket_name = bucket["Name"]

        versioning = s3.get_bucket_versioning(Bucket=bucket_name)
        status = versioning.get("Status")

        if status == "Enabled":
            finding = create_finding(
                "S3_VERSIONING",
                "PASS",
                "MEDIUM",
                bucket_name,
                "Bucket versioning is enabled",
            )
        else:
            finding = create_finding(
                "S3_VERSIONING",
                "FAIL",
                "MEDIUM",
                bucket_name,
                f"Bucket versioning is not enabled (status: {status})",
            )

        findings.append(finding)

    return findings

def check_ec2_public_ip():
    findings = []

    response = ec2.describe_instances()

    for reservation in response["Reservations"]:
        for instance in reservation["Instances"]:
            instance_id = instance["InstanceId"]
            state = instance["State"]["Name"]

            if state == "terminated":
                continue

            public_ip = instance.get("PublicIpAddress")

            if public_ip is None:
                finding = create_finding(
                    "EC2_PUBLIC_IP",
                    "PASS",
                    "HIGH",
                    instance_id,
                    "Instance has no public IPv4 address",
                )
            else:
                finding = create_finding(
                    "EC2_PUBLIC_IP",
                    "FAIL",
                    "HIGH",
                    instance_id,
                    f"Instance has public IPv4 address {public_ip}",
                )

            findings.append(finding)

    return findings

def check_ec2_imdsv2():
    findings = []

    response = ec2.describe_instances()

    for reservation in response["Reservations"]:
        for instance in reservation["Instances"]:
            instance_id = instance["InstanceId"]
            state = instance["State"]["Name"]

            if state == "terminated":
                continue

            http_tokens = instance["MetadataOptions"]["HttpTokens"]

            if http_tokens == "required":
                finding = create_finding(
                    "EC2_IMDSV2",
                    "PASS",
                    "HIGH",
                    instance_id,
                    "Instance requires IMDSv2",
                )
            else:
                finding = create_finding(
                    "EC2_IMDSV2",
                    "FAIL",
                    "HIGH",
                    instance_id,
                    "Instance allows IMDSv1-compatible metadata access",
                )

            findings.append(finding)

    return findings

def check_ec2_root_volume_encryption():
    findings = []

    response = ec2.describe_instances()

    for reservation in response["Reservations"]:
        for instance in reservation["Instances"]:
            instance_id = instance["InstanceId"]
            state = instance["State"]["Name"]

            if state == "terminated":
                continue

            root_device_name = instance["RootDeviceName"]

            for device in instance["BlockDeviceMappings"]:
                if device["DeviceName"] == root_device_name:
                    volume_id = device["Ebs"]["VolumeId"]

                    volume_response = ec2.describe_volumes(
                        VolumeIds=[volume_id]
                    )

                    volume = volume_response["Volumes"][0]
                    encrypted = volume["Encrypted"]

                    if encrypted:
                        finding = create_finding(
                            "EC2_ROOT_VOLUME_ENCRYPTION",
                            "PASS",
                            "HIGH",
                            instance_id,
                            f"Root volume {volume_id} is encrypted",
                        )
                    else:
                        finding = create_finding(
                            "EC2_ROOT_VOLUME_ENCRYPTION",
                            "FAIL",
                            "HIGH",
                            instance_id,
                            f"Root volume {volume_id} is not encrypted",
                        )

                    findings.append(finding)

    return findings

def check_security_group_public_ingress():
    findings = []

    response = ec2.describe_security_groups()

    for security_group in response["SecurityGroups"]:
        group_id = security_group["GroupId"]
        group_name = security_group["GroupName"]

        risky_rules = []

        for permission in security_group["IpPermissions"]:
            protocol = permission["IpProtocol"]

            if protocol != "tcp":
                continue

            from_port = permission.get("FromPort")
            to_port = permission.get("ToPort")

            if from_port is None or to_port is None:
                continue

            public_ipv4 = any(
                ip_range["CidrIp"] == "0.0.0.0/0"
                for ip_range in permission.get("IpRanges", [])
            )

            if not public_ipv4:
                continue

            for port, service in SENSITIVE_PORTS.items():
                if from_port <= port <= to_port:
                    risky_rules.append(f"{service} TCP/{port}")

        if risky_rules:
            finding = create_finding(
                "SG_PUBLIC_INGRESS",
                "FAIL",
                "HIGH",
                group_id,
                f"{group_name} exposes sensitive services publicly: {', '.join(risky_rules)}",
            )
        else:
            finding = create_finding(
                "SG_PUBLIC_INGRESS",
                "PASS",
                "HIGH",
                group_id,
                f"{group_name} does not expose sensitive TCP services to 0.0.0.0/0",
            )

        findings.append(finding)

    return findings

def check_private_subnet_default_routes():
    findings = []

    subnets = ec2.describe_subnets()["Subnets"]

    for subnet in subnets:
        subnet_id = subnet["SubnetId"]

        name = next(
            (
                tag["Value"]
                for tag in subnet.get("Tags", [])
                if tag["Key"] == "Name"
            ),
            "",
        )

        if "app" not in name.lower() and "data" not in name.lower():
            continue

        route_tables = ec2.describe_route_tables(
            Filters=[
                {
                    "Name": "association.subnet-id",
                    "Values": [subnet_id],
                }
            ]
        )["RouteTables"]

        has_default_route = False

        for route_table in route_tables:
            for route in route_table["Routes"]:
                if route.get("DestinationCidrBlock") == "0.0.0.0/0":
                    has_default_route = True

        if has_default_route:
            finding = create_finding(
                "PRIVATE_SUBNET_DEFAULT_ROUTE",
                "FAIL",
                "HIGH",
                subnet_id,
                f"{name} has an IPv4 default route",
            )
        else:
            finding = create_finding(
                "PRIVATE_SUBNET_DEFAULT_ROUTE",
                "PASS",
                "HIGH",
                subnet_id,
                f"{name} has no IPv4 default route",
            )

        findings.append(finding)

    return findings

def check_cloudtrail_enabled():
    findings = []

    trails = cloudtrail.describe_trails(
        includeShadowTrails=False
    )["trailList"]

    if not trails:
        findings.append(
            create_finding(
                "CLOUDTRAIL_ENABLED",
                "FAIL",
                "HIGH",
                "AWS_ACCOUNT",
                "No CloudTrail trails are configured",
            )
        )

        return findings

    for trail in trails:
        trail_name = trail["Name"]

        status = cloudtrail.get_trail_status(
            Name=trail["TrailARN"]
        )

        if status["IsLogging"]:
            finding = create_finding(
                "CLOUDTRAIL_ENABLED",
                "PASS",
                "HIGH",
                trail_name,
                "CloudTrail is actively logging",
            )
        else:
            finding = create_finding(
                "CLOUDTRAIL_ENABLED",
                "FAIL",
                "HIGH",
                trail_name,
                "CloudTrail exists but is not actively logging",
            )

        findings.append(finding)

    return findings

def check_vpc_flow_logs():
    findings = []

    vpcs = ec2.describe_vpcs()["Vpcs"]

    flow_logs = ec2.describe_flow_logs()["FlowLogs"]

    for vpc in vpcs:
        vpc_id = vpc["VpcId"]

        matching_logs = [
            flow_log
            for flow_log in flow_logs
            if flow_log["ResourceId"] == vpc_id
        ]

        active_logs = [
            flow_log
            for flow_log in matching_logs
            if flow_log["FlowLogStatus"] == "ACTIVE"
        ]

        if active_logs:
            finding = create_finding(
                "VPC_FLOW_LOGS",
                "PASS",
                "MEDIUM",
                vpc_id,
                "VPC has an active Flow Log",
            )
        else:
            finding = create_finding(
                "VPC_FLOW_LOGS",
                "FAIL",
                "MEDIUM",
                vpc_id,
                "VPC does not have an active Flow Log",
            )

        findings.append(finding)

    return findings

def check_required_vpc_endpoints():
    findings = []

    response = ec2.describe_vpc_endpoints()

    available_services = {
        endpoint["ServiceName"]
        for endpoint in response["VpcEndpoints"]
        if endpoint["State"] == "available"
    }

    for service in REQUIRED_VPC_ENDPOINT_SERVICES:
        short_name = service.split(".")[-1]

        if service in available_services:
            finding = create_finding(
                "VPC_ENDPOINT_REQUIRED",
                "PASS",
                "MEDIUM",
                short_name,
                f"Required VPC endpoint for {short_name} is available",
            )
        else:
            finding = create_finding(
                "VPC_ENDPOINT_REQUIRED",
                "FAIL",
                "MEDIUM",
                short_name,
                f"Required VPC endpoint for {short_name} is missing",
            )

        findings.append(finding)

    return findings

def check_cloudtrail_hardening():
    findings = []

    trails = cloudtrail.describe_trails(
        includeShadowTrails=False
    )["trailList"]

    for trail in trails:
        trail_name = trail["Name"]

        if trail.get("IsMultiRegionTrail"):
            findings.append(
                create_finding(
                    "CLOUDTRAIL_MULTI_REGION",
                    "PASS",
                    "MEDIUM",
                    trail_name,
                    "CloudTrail is configured as multi-region",
                )
            )
        else:
            findings.append(
                create_finding(
                    "CLOUDTRAIL_MULTI_REGION",
                    "FAIL",
                    "MEDIUM",
                    trail_name,
                    "CloudTrail is not configured as multi-region",
                )
            )

        if trail.get("LogFileValidationEnabled"):
            findings.append(
                create_finding(
                    "CLOUDTRAIL_LOG_VALIDATION",
                    "PASS",
                    "MEDIUM",
                    trail_name,
                    "CloudTrail log file validation is enabled",
                )
            )
        else:
            findings.append(
                create_finding(
                    "CLOUDTRAIL_LOG_VALIDATION",
                    "FAIL",
                    "MEDIUM",
                    trail_name,
                    "CloudTrail log file validation is disabled",
                )
            )

    return findings

def check_s3_encryption():
    findings = []

    response = s3.list_buckets()

    for bucket in response["Buckets"]:
        bucket_name = bucket["Name"]

        try:
            encryption = s3.get_bucket_encryption(
                Bucket=bucket_name
            )

            rules = encryption[
                "ServerSideEncryptionConfiguration"
            ]["Rules"]

            if rules:
                finding = create_finding(
                    "S3_ENCRYPTION",
                    "PASS",
                    "HIGH",
                    bucket_name,
                    "Bucket has server-side encryption configured",
                )
            else:
                finding = create_finding(
                    "S3_ENCRYPTION",
                    "FAIL",
                    "HIGH",
                    bucket_name,
                    "Bucket has no server-side encryption rules",
                )

        except s3.exceptions.ServerSideEncryptionConfigurationNotFoundError:
            finding = create_finding(
                "S3_ENCRYPTION",
                "FAIL",
                "HIGH",
                bucket_name,
                "Bucket has no server-side encryption configuration",
            )

        findings.append(finding)

    return findings

def check_secrets_manager_status():
    findings = []

    response = secretsmanager.list_secrets()

    for secret in response["SecretList"]:
        secret_name = secret["Name"]

        if "DeletedDate" in secret:
            finding = create_finding(
                "SECRET_ACTIVE",
                "FAIL",
                "MEDIUM",
                secret_name,
                "Secret is scheduled for deletion",
            )
        else:
            finding = create_finding(
                "SECRET_ACTIVE",
                "PASS",
                "MEDIUM",
                secret_name,
                "Secret is active",
            )

        findings.append(finding)

    return findings

def check_subnet_public_ip_assignment():
    findings = []

    subnets = ec2.describe_subnets()["Subnets"]

    for subnet in subnets:
        subnet_id = subnet["SubnetId"]

        name = next(
            (
                tag["Value"]
                for tag in subnet.get("Tags", [])
                if tag["Key"] == "Name"
            ),
            "",
        )

        if "app" not in name.lower() and "data" not in name.lower():
            continue

        auto_assign = subnet["MapPublicIpOnLaunch"]

        if auto_assign:
            finding = create_finding(
                "PRIVATE_SUBNET_PUBLIC_IP_AUTO_ASSIGN",
                "FAIL",
                "HIGH",
                subnet_id,
                f"{name} automatically assigns public IPv4 addresses",
            )
        else:
            finding = create_finding(
                "PRIVATE_SUBNET_PUBLIC_IP_AUTO_ASSIGN",
                "PASS",
                "HIGH",
                subnet_id,
                f"{name} does not automatically assign public IPv4 addresses",
            )

        findings.append(finding)

    return findings

def calculate_security_score(findings):
    total_possible = 0
    failed_points = 0

    for finding in findings:
        severity = finding["severity"]
        weight = SEVERITY_WEIGHTS[severity]

        total_possible += weight

        if finding["status"] == "FAIL":
            failed_points += weight

    if total_possible == 0:
        return 100

    score = 100 - ((failed_points / total_possible) * 100)

    return round(score, 1)

def print_summary(findings):
    total = len(findings)

    passed = 0
    failed = 0

    high_failures = 0
    medium_failures = 0
    low_failures = 0

    for finding in findings:
        if finding["status"] == "PASS":
            passed += 1

        elif finding["status"] == "FAIL":
            failed += 1

            if finding["severity"] == "HIGH":
                high_failures += 1
            elif finding["severity"] == "MEDIUM":
                medium_failures += 1
            elif finding["severity"] == "LOW":
                low_failures += 1

    score = calculate_security_score(findings)

    print()
    print("=== Security Scan Summary ===")
    print(f"Total findings: {total}")
    print(f"Passed: {passed}")
    print(f"Failed: {failed}")
    print()
    print(f"High severity failures: {high_failures}")
    print(f"Medium severity failures: {medium_failures}")
    print(f"Low severity failures: {low_failures}")
    print()
    print(f"Security score: {score}/100")

def write_json_report(findings, account_id, region):
    score = calculate_security_score(findings)

    report = {
        "scan_metadata": {
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "account_id": account_id,
            "region": region,
        },
        "summary": {
            "total_findings": len(findings),
            "passed": sum(
                1 for finding in findings
                if finding["status"] == "PASS"
            ),
            "failed": sum(
                1 for finding in findings
                if finding["status"] == "FAIL"
            ),
            "security_score": score,
        },
        "findings": findings,
    }

    with open("security_report.json", "w") as file:
        json.dump(report, file, indent=4)

    print()
    print("JSON report written to security_report.json")

def main():
    identity = sts.get_caller_identity()

    print("Connected to AWS successfully")
    print(f"Account: {identity['Account']}")
    print(f"ARN: {identity['Arn']}")
    print()

    all_findings = []

    all_findings.extend(check_s3_public_access())
    all_findings.extend(check_s3_versioning())
    all_findings.extend(check_ec2_public_ip())
    all_findings.extend(check_ec2_imdsv2())
    all_findings.extend(check_ec2_root_volume_encryption())
    all_findings.extend(check_security_group_public_ingress())
    all_findings.extend(check_private_subnet_default_routes())
    all_findings.extend(check_cloudtrail_enabled())
    all_findings.extend(check_vpc_flow_logs())
    all_findings.extend(check_required_vpc_endpoints())
    all_findings.extend(check_cloudtrail_hardening())
    all_findings.extend(check_s3_encryption())
    all_findings.extend(check_secrets_manager_status())
    all_findings.extend(check_subnet_public_ip_assignment())

    for finding in all_findings:
        print(
            f"[{finding['status']}] "
            f"{finding['check_id']} - "
            f"{finding['resource']} - "
            f"{finding['message']}"
        )
    print_summary(all_findings)
    write_json_report(
        all_findings,
        identity["Account"],
        session.region_name,
    )

    has_failures = any(
        finding["status"] == "FAIL"
        for finding in all_findings
    )

    if has_failures:
        sys.exit(1)

    sys.exit(0)

if __name__ == "__main__":
    main()