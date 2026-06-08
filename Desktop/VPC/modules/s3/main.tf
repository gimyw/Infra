resource "aws_s3_bucket" "main" {
  bucket = var.bucket_name

  tags = { Name = "${var.env}-s3" }
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket                  = aws_s3_bucket.main.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "main" {
  bucket                  = aws_s3_bucket.main.id
  cors_rule {
    allowed_origins = var.cors_allowed_origins
    allowed_methods = ["GET","PUT","POST","HEAD"]
    allowed_headers = ["*"]
    expose_headers = ["ETag"]
    max_age_seconds = 3000
  }
}

