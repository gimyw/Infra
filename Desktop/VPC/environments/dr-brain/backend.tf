terraform {
  backend "s3" {
    bucket         = "farmily-terraform-state"
    key            = "dr-brain/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
