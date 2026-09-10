# Preserve existing Terraform state while improving resource labels.
# These are address migrations only; they do not orovision new AWS resources.

moved {
  from = aws_subnet.public
  to   = aws_subnet.public_a
}

moved {
  from = aws_subnet.app
  to   = aws_subnet.app_a
}

moved {
  from = aws_subnet.data
  to   = aws_subnet.data_a
}

moved {
  from = aws_route_table_association.public
  to   = aws_route_table_association.public_a
}

moved {
  from = aws_route_table_association.app
  to   = aws_route_table_association.app_a
}

moved {
  from = aws_route_table_association.data
  to   = aws_route_table_association.data_a
}

moved {
  from = aws_security_group.public
  to   = aws_security_group.alb
}

moved {
  from = aws_vpc_security_group_ingress_rule.public_https
  to   = aws_vpc_security_group_ingress_rule.alb_https
}

moved {
  from = aws_vpc_security_group_ingress_rule.app_from_public
  to   = aws_vpc_security_group_ingress_rule.app_from_alb
}

moved {
  from = aws_vpc_security_group_egress_rule.public_to_app
  to   = aws_vpc_security_group_egress_rule.alb_to_app
}
