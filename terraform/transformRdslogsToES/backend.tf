terraform {
  backend "s3" {
    bucket               = "aws-jdf-terraform-state"
    encrypt              = true
    key                  = "rds-log-shipper"
    region               = "us-east-1"
    workspace_key_prefix = "rds-log-shipper"
  }
}
