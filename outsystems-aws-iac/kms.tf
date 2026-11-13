###############################################################################
# Customer-managed KMS key used for RDS, Secrets Manager, S3 artifacts,
# CloudWatch Logs and SNS. Rotation is enabled.
###############################################################################
data "aws_iam_policy_document" "kms" {
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid = "AllowAwsServicesToUseKey"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    principals {
      type = "Service"
      identifiers = [
        "logs.${var.aws_region}.amazonaws.com",
        "cloudwatch.amazonaws.com",
        "sns.amazonaws.com",
      ]
    }
  }
}

resource "aws_kms_key" "platform" {
  description             = "${local.name_prefix} OutSystems platform encryption key"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "platform" {
  name          = "alias/${local.name_prefix}-platform"
  target_key_id = aws_kms_key.platform.key_id
}
