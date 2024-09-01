Create a s3 bucket
Update _data.tf with your tags to describe vpc and subnet
Update var.tf to change number of nodes or the name of nodes
If you want to create specific password then remove auto generated pass block from main.tf and from var.tf you can directly pass the desired password same as username
After all the changes simply run :
terraform init
terraform plan
terraform apply
