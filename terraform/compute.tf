data "aws_ssm_parameter" "amazon_linux_2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_ebs_encryption_by_default" "main" {
  enabled = true
}

resource "aws_instance" "app" {
  count = var.enable_runtime_resources ? 1 : 0

  ami           = data.aws_ssm_parameter.amazon_linux_2023.value
  instance_type = "t3.micro"

  subnet_id                   = aws_subnet.app_a.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = false

  iam_instance_profile = aws_iam_instance_profile.ec2_ssm.name

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted = true
  }

  user_data_replace_on_change = true
  user_data                   = <<-EOF
    #!/bin/bash
    set -e

    mkdir -p /opt/secure-cloud-app

    cat > /opt/secure-cloud-app/index.html <<'HTML'
    <!DOCTYPE html>
    <html>
    <head>
        <title>Secure Cloud Infrastructure Lab</title>
    </head>
    <body>
        <h1>Secure Cloud Infrastructure Lab</h1>
        <p>Private EC2 application behind an HTTPS Application Load Balancer.</p>
    </body>
    </html>
    HTML

    cat > /etc/systemd/system/secure-cloud-app.service <<'SERVICE'
    [Unit]
    Description=Secure Cloud Application
    After=network.target

    [Service]
    Type=simple
    WorkingDirectory=/opt/secure-cloud-app
    ExecStart=/usr/bin/python3 -m http.server 8080
    Restart=always

    [Install]
    WantedBy=multi-user.target
    SERVICE

    systemctl daemon-reload
    systemctl enable secure-cloud-app
    systemctl start secure-cloud-app
  EOF

  tags = {
    Name        = "secure-cloud-app-instance"
    Project     = "secure-cloud-infrastructure"
    Environment = "lab"
  }
}