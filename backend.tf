
# terraform {
#   backend "s3" {
#     bucket = "yanashapkatest-terraform-state-lesson-7"
#     key            = "lesson-7/terraform.tfstate"
#     region         = "eu-north-1"
#     dynamodb_table = "terraform-locks"
#     encrypt        = true
#   }
# }