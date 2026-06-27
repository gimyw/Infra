terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1" # 도쿄(기본) — 두뇌가 사는 리전
}

provider "aws" {
  alias  = "seoul"
  region = "ap-northeast-2" # 서울 — 차단·FIS 단계(dr-4)에서 사용
}
