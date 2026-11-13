###############################################################################
# Instance role shared by controller and front-ends:
#  - SSM Session Manager / Run Command (replaces RDP)
#  - CloudWatch agent (IIS + Windows event logs, memory/disk metrics)
#  - read installers/config from the artifacts bucket
#  - read the DB master secret (used once by the Configuration Tool)
###############################################################################
resource "aws_iam_role" "instance" {
  name = "${var.name_prefix}-outsystems-server"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
  ])

  role       = aws_iam_role.instance.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "instance" {
  name = "outsystems-runtime-access"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "ReadArtifacts"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:ListBucket"]
          Resource = [var.artifacts_bucket_arn, "${var.artifacts_bucket_arn}/*"]
        },
        {
          Sid      = "DecryptPlatformKey"
          Effect   = "Allow"
          Action   = ["kms:Decrypt", "kms:DescribeKey"]
          Resource = var.kms_key_arn
        },
      ],
      var.db_secret_arn == null ? [] : [
        {
          Sid      = "ReadDatabaseSecret"
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          Resource = var.db_secret_arn
        },
      ],
    )
  })
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name_prefix}-outsystems-server"
  role = aws_iam_role.instance.name
}
