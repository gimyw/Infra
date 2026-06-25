// 이 모듈에는 tls 인증 (OIDC 인증)이 필요하므로 따로 프로바이더 버전을 명시함
terraform {
  required_providers {
    aws = {
        source  = "hashicorp/aws"
        version = "~> 5.0" 
    }
    tls = {
        source  = "hashicorp/tls"
        version = "~> 4.0"
    }
  }
}
