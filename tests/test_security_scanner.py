import unittest
from unittest.mock import patch

from scripts.security_scanner import (
    calculate_security_score,
    check_security_group_public_ingress,
)


class TestSecurityScore(unittest.TestCase):
    def test_all_pass_returns_100(self):
        findings = [
            {"status": "PASS", "severity": "HIGH"},
            {"status": "PASS", "severity": "MEDIUM"},
            {"status": "PASS", "severity": "LOW"},
        ]

        self.assertEqual(calculate_security_score(findings), 100.0)

    def test_empty_findings_returns_100(self):
        self.assertEqual(calculate_security_score([]), 100)

    def test_failed_high_finding_reduces_score(self):
        findings = [
            {"status": "FAIL", "severity": "HIGH"},
            {"status": "PASS", "severity": "HIGH"},
        ]

        self.assertEqual(calculate_security_score(findings), 50.0)


class TestSecurityGroupPublicIngress(unittest.TestCase):
    @patch("scripts.security_scanner.ec2")
    def test_public_ssh_is_detected(self, mock_ec2):
        mock_ec2.describe_security_groups.return_value = {
            "SecurityGroups": [
                {
                    "GroupId": "sg-test123",
                    "GroupName": "insecure-test-sg",
                    "IpPermissions": [
                        {
                            "IpProtocol": "tcp",
                            "FromPort": 22,
                            "ToPort": 22,
                            "IpRanges": [
                                {"CidrIp": "0.0.0.0/0"}
                            ],
                        }
                    ],
                }
            ]
        }

        findings = check_security_group_public_ingress()

        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0]["status"], "FAIL")
        self.assertEqual(findings[0]["severity"], "HIGH")
        self.assertIn("SSH TCP/22", findings[0]["message"])

    @patch("scripts.security_scanner.ec2")
    def test_https_only_is_not_flagged(self, mock_ec2):
        mock_ec2.describe_security_groups.return_value = {
            "SecurityGroups": [
                {
                    "GroupId": "sg-test456",
                    "GroupName": "public-alb-sg",
                    "IpPermissions": [
                        {
                            "IpProtocol": "tcp",
                            "FromPort": 443,
                            "ToPort": 443,
                            "IpRanges": [
                                {"CidrIp": "0.0.0.0/0"}
                            ],
                        }
                    ],
                }
            ]
        }

        findings = check_security_group_public_ingress()

        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0]["status"], "PASS")


if __name__ == "__main__":
    unittest.main()