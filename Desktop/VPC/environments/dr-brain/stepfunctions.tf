# Phase 3 — 전부 잇기 : 상태기계 (promote 없는 dry-run)
# 지금까지의 조각을 하나로 꿴다: 진단 → AI 분석 → 사람 승인 대기(waitForTaskToken).
# 승인되면 WouldFence(Succeed)로만 끝난다 — 실제 fence/promote는 Phase 4에서 붙인다.

data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "sfn" {
  name               = "dr-brain-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
}
resource "aws_iam_role_policy" "sfn" {
  name = "invoke-lambdas"
  role = aws_iam_role.sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["lambda:InvokeFunction"]
      Resource = [
        aws_lambda_function.diagnose.arn,
        aws_lambda_function.advisor.arn,
        aws_lambda_function.slack_notify.arn
      ]
    }]
  })
}

resource "aws_sfn_state_machine" "failover" {
  name     = "dr-brain-failover"
  role_arn = aws_iam_role.sfn.arn
  definition = jsonencode({
    Comment = "DR failover — Phase 3 dry-run (promote 없음)"
    StartAt = "Diagnose"
    States = {
      Diagnose = {
        Type       = "Task"
        Resource   = aws_lambda_function.diagnose.arn
        ResultPath = "$.diagnose"
        Next       = "AIAnalyze"
      }
      AIAnalyze = {
        Type       = "Task"
        Resource   = aws_lambda_function.advisor.arn
        Parameters = { "diagnose.$" = "$.diagnose" }
        ResultPath = "$.advisor"
        Next       = "PostApproval"
      }
      PostApproval = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke.waitForTaskToken"
        Parameters = {
          FunctionName = aws_lambda_function.slack_notify.arn
          Payload = {
            "taskToken.$" = "$$.Task.Token"
            "advice_ko.$" = "$.advisor.advice_ko"
          }
        }
        TimeoutSeconds = 900 # 15분 무응답이면 실행 종료
        ResultPath     = "$.approval"
        Next           = "Decide"
      }
      Decide = {
        Type = "Choice"
        Choices = [{
          Variable      = "$.approval.approved"
          BooleanEquals = true
          Next          = "WouldFence"
        }]
        Default = "Rejected"
      }
      WouldFence = { Type = "Succeed" } # Phase 4에서 여기에 fence→promote→flip을 붙인다
      Rejected   = { Type = "Succeed" }
    }
  })
}
