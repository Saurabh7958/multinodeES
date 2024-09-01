# Create security group allowing inbound traffic on necessary ports
resource "aws_security_group" "es_security_group" {
  name        = "es-security-group" #security group name
  description = "Security group for Elasticsearch cluster"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  #vpc cidr
  }
  ingress {
    from_port   = 9300
    to_port     = 9300
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] #vpc cidr
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
 tags = {
    Name = "elasticsearch-sg" #Tags you want to add 
  }
}


