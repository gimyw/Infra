resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.env}-redis-subnet-group"
  subnet_ids = var.private_subnet_ids
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.env}-redis"
  description          = "${var.env} Redis cluster"
  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_clusters
  engine_version       = var.engine_version
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = var.security_group_ids
  automatic_failover_enabled = var.num_cache_clusters > 1
  transit_encryption_enabled = var.transit_encryption_enabled
  transit_encryption_mode    = var.transit_encryption_enabled ? var.transit_encryption_mode : null
  apply_immediately          = true

  tags = { Name = "${var.env}-redis" }
}
