# Phase 2 — 좌표(coordinator) + 알림 토픽
# "지금 누가 primary이고, fence/promote가 진행 중인가"를 단 한 곳에서 들고 있는 표.
# 앞으로 모든 단계(탐지·fence·promote·flip)가 이 좌표를 읽고 쓴다.
resource "aws_dynamodb_table" "coordinator" {
  name         = "dr-brain-coordinator"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "key"
  attribute {
    name = "key"
    type = "S"
  }

  tags = { Name = "dr-brain-coordinator" }
}

# 장애·승인 알림용 SNS 토픽 (canary가 여기로 publish)
resource "aws_sns_topic" "approvals" {
  name = "dr-brain-approvals"

  tags = { Name = "dr-brain-approvals" }
}

# 초기 상태 한 줄 seed — apply 후 1회, CLI로 직접 넣는다(테이블 자체는 비어서 생성됨):
#   aws dynamodb put-item --region ap-northeast-1 --table-name dr-brain-coordinator \
#     --item '{"key":{"S":"primary"},"current_primary":{"S":"seoul"},"epoch":{"N":"0"},
#              "fencing_in_progress":{"BOOL":false}}'
