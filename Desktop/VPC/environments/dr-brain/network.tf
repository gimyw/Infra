# diagnose Lambda 전용 보안그룹 (egress 전체)
resource "aws_security_group" "diagnose_lambda" {
  name        = "dr-brain-diagnose-lambda-sg"
  description = "dr-brain diagnose lambda"
  vpc_id      = data.aws_vpc.dr.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "dr-brain-diagnose-lambda-sg" }
}

# dr-rds-sg 가 위 lambda SG 로부터 5432 인바운드를 허용하도록 규칙 추가.
# (dr-rds-sg 에는 자기참조/Lambda 인바운드 규칙이 없어, 안 넣으면 diagnose 가 못 닿는다.)
#
# ⚠️ 검수 포인트: dr-rds-sg 는 environments/dr 의 sg 모듈이 'inline ingress' 로 관리한다.
#    environments/dr 를 다시 apply 하면 아래 standalone 규칙이 지워질 수 있다(drift 제거).
#    영구히 하려면 environments/dr/main.tf 의 sg 모듈에서 enable_lambda_sg=true 로 하거나,
#    이 규칙을 modules/sg 안으로 옮기는 게 깔끔하다. 부트캠프 단발 실습이면 이대로도 동작.
resource "aws_security_group_rule" "rds_from_diagnose" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = data.aws_security_group.dr_rds.id
  source_security_group_id = aws_security_group.diagnose_lambda.id
  description              = "dr-brain diagnose lambda to dr-rds 5432"
}
