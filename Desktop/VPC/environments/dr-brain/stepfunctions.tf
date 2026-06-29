# Phase 4 — 전부 잇기 : 상태기계 (arm_promote로 비가역 동작을 게이트)
# Phase 3의 WouldFence(빈 자리)를 실제 Fence → Promote → (완료 폴링) → Flip → Verify로 교체.
# 모든 위험 동작은 입력 플래그 arm_promote 뒤에 둔다 — 기본 false면 fence·promote가 no-op(로그만).
# promote 완료 대기는 별도 람다 없이 Step Functions의 AWS-SDK 통합(describeDBInstances)으로 폴링.

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
    Statement = [
      {
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = [
          aws_lambda_function.diagnose.arn,
          aws_lambda_function.advisor.arn,
          aws_lambda_function.slack_notify.arn,
          aws_lambda_function.fence.arn,
          aws_lambda_function.promote.arn,
          aws_lambda_function.flip.arn,
          aws_lambda_function.verify.arn,
          aws_lambda_function.audit_agent.arn,  # Phase 7
          aws_lambda_function.retrospective.arn # Phase 5
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["rds:DescribeDBInstances"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"] # Phase 7 NotifyAndPage
        Resource = aws_sns_topic.approvals.arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "failover" {
  name     = "dr-brain-failover"
  role_arn = aws_iam_role.sfn.arn
  definition = jsonencode({
    Comment = "DR failover — 최종(arm_promote로 비가역 동작 게이트)"
    StartAt = "Diagnose"
    States = {
      Diagnose  = { Type = "Task", Resource = aws_lambda_function.diagnose.arn, ResultPath = "$.diagnose", Next = "AIAnalyze" }
      AIAnalyze = { Type = "Task", Resource = aws_lambda_function.advisor.arn, Parameters = { "diagnose.$" = "$.diagnose" }, ResultPath = "$.advisor", Next = "PostApproval" }
      PostApproval = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke.waitForTaskToken"
        Parameters = {
          FunctionName = aws_lambda_function.slack_notify.arn
          Payload      = { "taskToken.$" = "$$.Task.Token", "advice_ko.$" = "$.advisor.advice_ko", "arm_promote.$" = "$.arm_promote" }
        }
        TimeoutSeconds = 900
        ResultPath     = "$.approval"
        Next           = "Decide"
      }
      Decide      = { Type = "Choice", Choices = [{ Variable = "$.approval.approved", BooleanEquals = true, Next = "Fence" }], Default = "Rejected" }
      Fence       = { Type = "Task", Resource = aws_lambda_function.fence.arn, Parameters = { "arm_promote.$" = "$.arm_promote" }, ResultPath = "$.fence", Next = "ArmGate" }
      ArmGate     = { Type = "Choice", Choices = [{ Variable = "$.arm_promote", BooleanEquals = true, Next = "FenceOk" }], Default = "DryRunDone" }
      FenceOk     = { Type = "Choice", Choices = [{ Variable = "$.fence.fenced", BooleanEquals = true, Next = "Promote" }], Default = "FenceFailed" }
      Promote     = { Type = "Task", Resource = aws_lambda_function.promote.arn, Parameters = { "arm_promote.$" = "$.arm_promote" }, ResultPath = "$.promote", Next = "WaitPromote" }
      WaitPromote = { Type = "Wait", Seconds = 30, Next = "DescribePromote" }
      DescribePromote = {
        Type       = "Task"
        Resource   = "arn:aws:states:::aws-sdk:rds:describeDBInstances"
        Parameters = { DbInstanceIdentifier = "dr-rds" }
        ResultPath = "$.desc"
        Next       = "PromoteReady"
      }
      PromoteReady = {
        Type    = "Choice"
        Choices = [{ Variable = "$.desc.DbInstances[0].DbInstanceStatus", StringEquals = "available", Next = "Flip" }]
        Default = "WaitPromote"
      }
      Flip = {
        Type     = "Task"
        Resource = aws_lambda_function.flip.arn
        Parameters = {
          promote = { "endpoint.$" = "$.desc.DbInstances[0].Endpoint.Address" }
          fence   = { "epoch.$" = "$.fence.epoch" }
        }
        ResultPath = "$.flip"
        Next       = "Verify"
      }
      Verify = { Type = "Task", Resource = aws_lambda_function.verify.arn, ResultPath = "$.verify", Next = "VerifyJudge" }
      # Phase 7 — 검수 에이전트(읽기전용 조사) → 결정론 rule_verdict로 분기
      VerifyJudge = {
        Type       = "Task"
        Resource   = aws_lambda_function.audit_agent.arn
        Parameters = { "verify.$" = "$.verify" }
        ResultPath = "$.audit"
        Next       = "AuditGate"
      }
      AuditGate = {
        Type    = "Choice"
        Choices = [{ Variable = "$.audit.rule_verdict", StringEquals = "ok", Next = "Retrospective" }]
        Default = "NotifyAndPage" # 의심/분열이면 먼저 시끄럽게 알린다
      }
      NotifyAndPage = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.approvals.arn
          Subject     = "[DR] Failover 검수 — 사람 확인 필요"
          "Message.$" = "$.audit.audit_ko"
        }
        ResultPath = "$.paged"
        Next       = "Retrospective" # 알린 뒤에도 회고는 남긴다
      }
      # Phase 5 — 어느 경로든 마지막에 회고를 남긴다(실측 RTO/RPO)
      Retrospective = {
        Type     = "Task"
        Resource = aws_lambda_function.retrospective.arn
        Parameters = {
          "executionArn.$" = "$$.Execution.Id"
          "diagnose.$"     = "$.diagnose"
          "audit.$"        = "$.audit"
        }
        ResultPath = "$.retro"
        Next       = "Done"
      }
      Done        = { Type = "Succeed" }
      DryRunDone  = { Type = "Succeed" }
      Rejected    = { Type = "Succeed" }
      FenceFailed = { Type = "Fail", Error = "FenceFailed" }
    }
  })
}
