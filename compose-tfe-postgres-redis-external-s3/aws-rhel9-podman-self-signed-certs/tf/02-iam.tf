resource "aws_iam_role" "this" {
  name_prefix        = "${var.resource_prefix}-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_instance_profile" "this" {
  name_prefix = "${var.resource_prefix}-profile"
  role        = aws_iam_role.this.name
}

resource "aws_iam_role_policy_attachment" "ssm" {
  policy_arn = data.aws_iam_policy.amazon_ssm_managed_instance_core.arn
  role       = aws_iam_role.this.name
}
