resource "aws_db_subnet_group" "main" {
  name       = "${var.env}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = { Name = "${var.env}-db-subnet-group" }
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

  tags = { Name = "${var.env}-rds" }
}
