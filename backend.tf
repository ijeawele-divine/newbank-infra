terraform {
  backend "s3" {
    bucket = "newbank-terraform-state"
    key = "prod-terraform.tfstate"
    region = "eu-north-1"
    dynamodb_table = "newbank-terraform-locks"
    encrypt = true
  }
}