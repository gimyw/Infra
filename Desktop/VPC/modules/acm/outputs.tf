output "certificate_arn" {
  # 검증 완료된 인증서 ARN (validation 의존성 포함)
  value = aws_acm_certificate_validation.this.certificate_arn
}
