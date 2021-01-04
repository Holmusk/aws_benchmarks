provider "aws" {
    version = "~> 2.7"
    region  = "ap-southeast-1"
}

resource "aws_s3_bucket" "test-upload-bucket" {
  bucket = "benchmark-test-upload-bucket"
  acl    = "private"
  
  force_destroy = true
}

resource "aws_sqs_queue" "test-upload-queue" {
  name = "benchmark-test-upload-queue"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "sqs:SendMessage",
      "Resource": "arn:aws:sqs:*:*:benchmark-test-upload-queue",
      "Condition": {
        "ArnEquals": { "aws:SourceArn": "${aws_s3_bucket.test-upload-bucket.arn}" }
      }
    }
  ]
}
POLICY
}

resource "aws_s3_bucket_notification" "test-bucket-notification" {
  bucket = aws_s3_bucket.test-upload-bucket.id

  queue {
    queue_arn     = aws_sqs_queue.test-upload-queue.arn
    events        = ["s3:ObjectCreated:*"]
  }
}

