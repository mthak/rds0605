provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

variable "component" {}

variable "cloud_watch_logs_role_arn" {}
variable "cloudtrail_name" {}
variable "environment" {}
variable "esdomain" {}
variable "event_name" {}
variable "git_commit" {}
variable "id" {}
variable "lambda_function_arn" {}
variable "s3_environment" {}
variable "name" {}
//variable "rdslogs3bucket" {}
variable "s3_bucket" {}
variable "s3_name" {}
variable "s3_path" {}

variable "security_group_ids" {
  default = "sg-ad2272da"
}

variable "subnet_ids" {
  type = "list"
}

variable "vpc" {
  type = "string"
}

data "aws_security_group" "security_group_ids" {
  id = "${var.security_group_ids}"
}

//Create RDS to S3 Function
resource "aws_lambda_function" "Rds_to_S3" {
  description   = "Ship RDS logs to S3"
  function_name = "jdf-ops-ship-rds-logs-to-s3-tf"
  handler       = "rds_log_ship.lambda_handler"
  memory_size   = "750"
  timeout       = "300"
  runtime       = "python2.7"
  role          = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ops/rds-log-export"
  s3_bucket     = "${var.s3_bucket}"
  s3_key        = "${var.s3_path}/Rds_to_S3-${var.git_commit}.zip"

  environment {
    variables = {
      // Name      = "${var.s3_environment}"
      s3_bucket = "${var.s3_bucket}"
    }
  }

  tags {
    component = "${var.component}"
    Name      = "${var.s3_name}"
  }
}

resource "aws_cloudwatch_event_rule" "jdf-ops-ship-RDS-logs-to-jdfOpsShipRdsLogsToS3Shipper" {
  name                = "${var.event_name}"
  description         = "Fires everyhour past 5"
  schedule_expression = "cron(5 * * * ? *)"

  depends_on = [
    "aws_lambda_function.Rds_to_S3",
  ]
}

resource "aws_cloudwatch_event_target" "check_lambda_everyhour_past_five" {
  rule      = "${aws_cloudwatch_event_rule.jdf-ops-ship-RDS-logs-to-jdfOpsShipRdsLogsToS3Shipper.name}"
  target_id = "Rds_to_S3"
  arn       = "${aws_lambda_function.Rds_to_S3.arn}"
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_Rds_to_S3" {
  statement_id  = "AllowExecutionFromCloudWatch-call_Rds_to_S3"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.Rds_to_S3.function_name}"
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.jdf-ops-ship-RDS-logs-to-jdfOpsShipRdsLogsToS3Shipper.arn}"
}

//Create S3 to ES Function
resource "aws_lambda_function" "s3-to-es" {
  description   = "Transform RDS logs from S3 and send to ES"
  function_name = "jdf-ops-transform-rds-logs-to-es-tf"
  handler       = "index.handler"
  memory_size   = "256"
  timeout       = "300"
  runtime       = "nodejs6.10"
  role          = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ops/rds-log-export"
  s3_bucket     = "${var.s3_bucket}"
  s3_key        = "${var.s3_path}/s3-to-es-${var.git_commit}.zip"

    vpc_config {
      security_group_ids = [
        "${var.security_group_ids}",
      ]

    subnet_ids = [
      "${var.subnet_ids}",
    ]
  }

  environment {
    variables = {
      ES_DOMAIN = "${var.esdomain}"
    }
  }

  tags {
    component = "${var.component}"
    Name      = "${var.name}"
  }
}

resource "aws_lambda_permission" "allow_es_policy" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.s3-to-es.function_name}"
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.s3_bucket}"
}

data "aws_s3_bucket" "lists3bucket" {
  bucket = "${var.s3_bucket}"
}

resource "aws_lambda_permission" "allow_rdslogs3bucket_policy" {
  statement_id = "AllowExecutionFromS3Buckets"
  action       = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.s3-to-es.function_name}"
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.s3_bucket}"
}

resource "aws_s3_bucket_notification" "rdsbucket_notification" {
  //bucket = "${data.aws_s3_bucket.lists3bucket.id}"
  bucket = "${var.s3_bucket}"

   lambda_function {
    id                  = "${var.id}"
    lambda_function_arn = "${var.lambda_function_arn}"

    events = [
      //"s3:ObjectCreated:Put",
      "s3:ObjectCreated:Put",
    ]

    filter_prefix = "RDS/"
    filter_suffix = ".log"
  }
}

/*data "aws_s3_bucket" "cloudtrailbucket" {
  bucket = "${var.rdslogs3bucket}"
}

resource "aws_cloudtrail" "SendToCloudTrailLambda" {
  name                      = "${var.cloudtrail_name}"
  s3_bucket_name            = "${data.aws_s3_bucket.cloudtrailbucket.bucket}"
  s3_key_prefix             = "AWSCloudTrail/"
  cloud_watch_logs_role_arn = "${var.cloud_watch_logs_role_arn}"
  enable_logging            = true


  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type = "AWS::S3::Object"

      values = [
        //  "arn:aws:s3::${var.rdslogs3bucket}"]
        "${data.aws_s3_bucket.cloudtrailbucket.arn}/",
      ]
    }
  }
}*/

