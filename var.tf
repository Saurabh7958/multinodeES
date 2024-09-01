variable "aws_region" {
  default = "us-east-2"  # Update with your desired AWS region
}

variable "instance_type" {
  default = "m6g.xlarge"  # Update with your desired instance type
}

variable "ami_id" {
  default = "ami-09e8371d89"  # Update with your desired AMI ID for Amazon Linux 2
}

variable "elastic_user" {
  default = "user"  # Update with your desired Elasticsearch user
}

variable "instance_name_master" {
  description = "Name for master nodes"
  default     = "multinode-master-es"
}

variable "instance_name_data" {
  description = "Name for data nodes"
  default     = "multinode-data-es"
}
variable "bucket_name" {
  description = "Name of the S3 bucket containing certificates"
  default     = "demo"
}

variable "master_count" {
  description = "Number of master nodes"
  default     = 2
}

variable "data_count" {
  description = "Number of data nodes"
  default     = 2
}

