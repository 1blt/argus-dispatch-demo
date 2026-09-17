# Intentionally insecure Terraform, used as a fixture for the IaC scanners.
#
# I1 (infrastructure-scan.yml) and W1 (reusable-security-hardening.yml with
# scanners: trivy-iac) previously ran against the default iac_path of
# "infrastructure", which does not exist in this repo -- so both passed by
# scanning nothing. These resources trip well-known checkov and trivy-iac rules,
# so a scanner that stops reporting is visible as a change in findings rather
# than as a silent green.
#
# Nothing here is deployed. Do not copy it.

terraform {
  required_version = ">= 1.0"
}

provider "aws" {
  region = "us-east-1"
}

# CKV_AWS_20 / CKV_AWS_53-56: public bucket, no encryption, no versioning.
resource "aws_s3_bucket" "fixture_public" {
  bucket = "argus-test-fixture-public-bucket"
}

resource "aws_s3_bucket_public_access_block" "fixture_public" {
  bucket                  = aws_s3_bucket.fixture_public.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# CKV_AWS_24: SSH open to the world.
resource "aws_security_group" "fixture_open_ssh" {
  name        = "argus-test-fixture-open-ssh"
  description = "Fixture security group with unrestricted ingress"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# CKV_AWS_16 / CKV_AWS_161: unencrypted database with a hardcoded password.
resource "aws_db_instance" "fixture_unencrypted" {
  identifier          = "argus-test-fixture-db"
  engine              = "mysql"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  username            = "admin"
  password            = "hunter2-fixture-not-a-real-secret"
  storage_encrypted   = false
  publicly_accessible = true
  skip_final_snapshot = true
}
