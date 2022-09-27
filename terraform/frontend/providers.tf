terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.32"
    }
  }
}

provider "aws" {
  alias = "virginia"
  region = "us-east-1"
  default_tags {
      tags = {
        Project = "parking-lot"
        Type = "frontend"
      }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
  default_tags {
      tags = {
        Project = "parking-lot"
        Type = "frontend"
      }
  }
}
