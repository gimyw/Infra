terraform {
  backend "s3" {
    bucket         = "farmily-terraform-state"
    key            = "jenkins/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
