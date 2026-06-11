resource "aws_security_group" "alb" {
  name        = "${var.env}-alb-sg"
  description = "ALB security group"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env}-alb-sg" }
}

resource "aws_security_group" "ecs" {
  name        = "${var.env}-ecs-sg"
  description = "ECS security group"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env}-ecs-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${var.env}-rds-sg"
  description = "RDS security group"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  dynamic "ingress" {
    for_each = var.enable_lambda_sg ? [1] : []
    content {
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [aws_security_group.lambda[0].id]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env}-rds-sg" }
}

resource "aws_security_group" "redis" {
  name        = "${var.env}-redis-sg"
  description = "Redis security group"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env}-redis-sg" }
}

resource "aws_security_group" "lambda" {
  count       = var.enable_lambda_sg ? 1 : 0
  name        = "${var.env}-lambda-sg"
  description = "Lambda functions RDS access"
  vpc_id      = var.vpc_id

  # 인바운드 없음 (Lambda는 아웃바운드로 RDS에 접속)

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env}-lambda-sg" }
}
