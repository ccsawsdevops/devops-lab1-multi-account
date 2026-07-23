terraform {
  required_version = ">= 1.3.0"
  backend "s3" {
    bucket         = "devops-tfstate-631412642519-lab1"
    key            = "egress/networking/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# --- CENTRAL EGRESS / DMZ VPC ---
module "egress_vpc" {
  source               = "../../modules/vpc"
  environment          = "central-egress"
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]
}

# --- NAT GATEWAY FOR OUTBOUND INTERNET ---
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags   = { Name = "egress-nat-eip" }
}

resource "aws_nat_gateway" "central_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = module.egress_vpc.public_subnet_ids[0]

  tags = { Name = "central-egress-nat" }
}

# --- ROUTE NAT TRAFFIC TO INTERNET ---
resource "aws_route" "egress_default_route" {
  route_table_id         = module.egress_vpc.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.central_nat.id
}
# --- TGW ATTACHMENT FOR EGRESS VPC ---
resource "aws_ec2_transit_gateway_vpc_attachment" "egress_attachment" {
  transit_gateway_id = "tgw-0a9c37e459e07a481"
  vpc_id             = module.egress_vpc.vpc_id
  subnet_ids         = module.egress_vpc.private_subnet_ids

  tags = { Name = "tgw-attachment-egress-vpc" }
}

# --- ROUTE TRAFFIC FROM TGW TO NAT GATEWAY ---
#resource "aws_route" "tgw_to_nat" {
#  route_table_id         = module.egress_vpc.private_route_table_id
#  destination_cidr_block = "0.0.0.0/0"
#  nat_gateway_id         = aws_nat_gateway.central_nat.id
#}
