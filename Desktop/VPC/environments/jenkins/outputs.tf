output "jenkins_ec2_role_arn" {
  description = "Jenkins EC2 인스턴스 프로파일에 부착하는 역할 ARN"
  value       = aws_iam_role.jenkins_ec2.arn
}

output "jenkins_ec2_instance_profile_name" {
  description = "EC2 Launch Template에 지정할 인스턴스 프로파일 이름"
  value       = aws_iam_instance_profile.jenkins_ec2.name
}

output "tf_runner_dev_arn" {
  description = "Jenkinsfile ROLE_ARN (dev) — main.tf ROLE_ARN 변수와 일치 확인용"
  value       = aws_iam_role.tf_runner_dev.arn
}

output "tf_runner_prod_arn" {
  description = "Jenkinsfile ROLE_ARN (prod) — main.tf ROLE_ARN 변수와 일치 확인용"
  value       = aws_iam_role.tf_runner_prod.arn
}
