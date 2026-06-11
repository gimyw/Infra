output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "ecs_sg_id" {
  value = aws_security_group.ecs.id
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}

output "redis_sg_id" {
  value = aws_security_group.redis.id
}

output "lambda_sg_id" {
  value = one(aws_security_group.lambda[*].id)
}

output "noti_lambda_sg_id" {
  value = one(aws_security_group.noti_lambda[*].id)
}
