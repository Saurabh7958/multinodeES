resource "aws_iam_role" "ec2_multinodeES_role" {
  name = "test-multinodeES-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}
resource "aws_iam_policy" "describe_ec2_instances_policy" {
  name        = "test-DescribeEC2InstancesPolicy"
  description = "Policy to allow describing EC2 instances"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "ec2:DescribeInstances",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "describe_ec2_instances_attachment" {
  role       = aws_iam_role.ec2_multinodeES_role.name
  policy_arn = aws_iam_policy.describe_ec2_instances_policy.arn
}

resource "aws_iam_role_policy_attachment" "ec2_multinodeES_role_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.ec2_multinodeES_role.name
}

resource "aws_iam_instance_profile" "multinodeES_instance_profile" {
  name = "test-multinodeES-role"
  role = aws_iam_role.ec2_multinodeES_role.name

}


resource "aws_iam_role_policy_attachment" "s3_access_policy_attachement" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.ec2_multinodeES_role.name
}
