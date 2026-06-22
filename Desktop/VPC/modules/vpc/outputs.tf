output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_a_id" {
  value = aws_subnet.public_a.id
}

output "public_subnet_c_id" {
  value = aws_subnet.public_c.id
}

output "private_subnet_a_id" {
  value = aws_subnet.private_a.id
}

output "private_subnet_c_id" {
  value = aws_subnet.private_c.id
}

output "private_db_subnet_a_id" {
  value = one(aws_subnet.private_db_a[*].id)
}

output "private_db_subnet_c_id" {
  value = one(aws_subnet.private_db_c[*].id)
}
