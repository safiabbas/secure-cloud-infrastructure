resource "aws_lb" "app" {
  count = var.enable_runtime_resources ? 1 : 0

  name               = "secure-cloud-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb.id
  ]

  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id,
  ]

  enable_deletion_protection = false

  tags = {
    Name = "secure-cloud-alb"
  }

  #checkov:skip=CKV2_AWS_28:WAF omitted for cost and scope in this security lab; production deployment would use AWS WAF
}

resource "aws_lb_target_group" "app" {
  count = var.enable_runtime_resources ? 1 : 0

  name     = "secure-cloud-app-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  target_type = "instance"

  health_check {
    enabled  = true
    protocol = "HTTP"
    port     = "traffic-port"
    path     = "/"
  }

  tags = {
    Name = "secure-cloud-app-target-group"
  }
}

resource "aws_lb_target_group_attachment" "app" {
  count = var.enable_runtime_resources ? 1 : 0

  target_group_arn = aws_lb_target_group.app[0].arn
  target_id        = aws_instance.app[0].id
  port             = 8080
}

resource "aws_lb_listener" "https" {
  count = var.enable_runtime_resources ? 1 : 0

  load_balancer_arn = aws_lb.app[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"

  certificate_arn = "arn:aws:acm:us-east-1:134604471209:certificate/469fd7ba-23d7-4c46-af47-3d68e71d891f"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[0].arn
  }
}