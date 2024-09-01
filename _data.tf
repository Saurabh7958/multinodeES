data "aws_vpc" "selected" {
  filter {
    name   = "tag:Environment"
    values = [local.workspace.environment_name]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:Scope"
    values = ["public"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "tag:Scope"
    values = ["private"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
}

data "aws_subnets" "database" {
  filter {
    name   = "tag:Scope"
    values = ["database"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
}

