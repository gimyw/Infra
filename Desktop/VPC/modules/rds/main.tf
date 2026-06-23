resource "aws_db_subnet_group" "main" {
  name       = "${var.env}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = { Name = "${var.env}-db-subnet-group" }
}

resource "aws_iam_role" "rds_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0
  name  = "${var.env}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count      = var.monitoring_interval > 0 ? 1 : 0
  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}


resource "aws_db_instance" "replica" {
  count = var.enable_read_replica ? 1 : 0

  identifier             = "${var.env}-rds-replica"
  replicate_source_db    = aws_db_instance.main.arn
  instance_class         = var.replica_instance_class
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = var.security_group_ids
  multi_az               = false
  publicly_accessible    = false
  skip_final_snapshot    = true
  monitoring_interval    = 0

  tags = { Name = "${var.env}-rds-replica" }
}

resource "aws_db_instance" "main" {
  identifier              = "${var.env}-rds"
  engine                  = "postgres"
  engine_version          = var.engine_version
  instance_class          = var.instance_class
  allocated_storage       = var.allocated_storage
  db_name                 = var.db_name
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = var.security_group_ids
  multi_az                = var.multi_az
  skip_final_snapshot     = true
  backup_retention_period = var.multi_az ? 7 : 1
  monitoring_interval     = var.monitoring_interval
  monitoring_role_arn     = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null

  tags = { Name = "${var.env}-rds" }

  lifecycle {
    # db_name·username·password는 생성 후 변경 시 replacement 발생
    # SSM 파라미터 값 변동으로 인한 의도치 않은 DB 교체 방지
    ignore_changes = [db_name, username, password]
  }
}

