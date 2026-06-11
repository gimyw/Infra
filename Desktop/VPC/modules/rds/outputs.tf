output "endpoint" {
  value = aws_db_instance.main.endpoint
}

output "address" {
  value = aws_db_instance.main.address
}

output "db_name" {
  value = aws_db_instance.main.db_name
}

output "replica_endpoint" {
  value = one(aws_db_instance.replica[*].endpoint)
}

output "replica_address" {
  value = one(aws_db_instance.replica[*].address)
}