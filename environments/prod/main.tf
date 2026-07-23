terraform {
  required_version = ">= 1.3.0"
  backend "s3" {
    bucket         = "devops-tfstate-631412642519-lab1"
    key            = "prod/networking/terraform.tfstate"
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

# --- SPOKE 1: App VPC ---
module "app_vpc" {
  source               = "../../modules/vpc"
  environment          = "prod-app"
  vpc_cidr             = "10.1.0.0/16"
  public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
  private_subnet_cidrs = ["10.1.10.0/24", "10.1.20.0/24"]
}

# --- SPOKE 2: Data VPC ---
module "data_vpc" {
  source               = "../../modules/vpc"
  environment          = "prod-data"
  vpc_cidr             = "10.2.0.0/16"
  public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
  private_subnet_cidrs = ["10.2.10.0/24", "10.2.20.0/24"]
}

# --- CENTRAL ROUTER: Transit Gateway ---
resource "aws_ec2_transit_gateway" "central_tgw" {
  description                     = "Enterprise Central Transit Gateway"
  auto_accept_shared_attachments = "enable"
  dns_support                     = "enable"

  tags = {
    Name = "prod-central-tgw"
  }
}

# Attach App VPC to TGW
resource "aws_ec2_transit_gateway_vpc_attachment" "app_attachment" {
  transit_gateway_id = aws_ec2_transit_gateway.central_tgw.id
  vpc_id             = module.app_vpc.vpc_id
  subnet_ids         = module.app_vpc.private_subnet_ids

  tags = { Name = "tgw-attachment-app-vpc" }
}

# Attach Data VPC to TGW
resource "aws_ec2_transit_gateway_vpc_attachment" "data_attachment" {
  transit_gateway_id = aws_ec2_transit_gateway.central_tgw.id
  vpc_id             = module.data_vpc.vpc_id
  subnet_ids         = module.data_vpc.private_subnet_ids

  tags = { Name = "tgw-attachment-data-vpc" }
}

# --- ROUTING RULES ---
resource "aws_route" "app_to_data" {
  route_table_id         = module.app_vpc.private_route_table_id
  destination_cidr_block = "10.2.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.central_tgw.id
}

resource "aws_route" "data_to_app" {
  route_table_id         = module.data_vpc.private_route_table_id
  destination_cidr_block = "10.1.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.central_tgw.id
}

# --- SSM IAM ROLE FOR SESSION MANAGER ---
resource "aws_iam_role" "ssm_role" {
  name = "tgw_test_ssm_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "tgw_test_ssm_profile"
  role = aws_iam_role.ssm_role.name
}

# --- AMAZON LINUX 2023 AMI ---
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# --- APP VPC TEST INSTANCE ---
resource "aws_security_group" "app_test_sg" {
  name   = "app-vpc-test-sg"
  vpc_id = module.app_vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app_test_instance" {
  ami                  = data.aws_ami.amazon_linux.id
  instance_type        = "t3.micro"
  subnet_id            = module.app_vpc.private_subnet_ids[0]
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name
  vpc_security_group_ids = [aws_security_group.app_test_sg.id]

  tags = { Name = "App-VPC-Test-Instance" }
}

# --- DATA VPC TEST INSTANCE ---
resource "aws_security_group" "data_test_sg" {
  name   = "data-vpc-test-sg"
  vpc_id = module.data_vpc.vpc_id

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.1.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "data_test_instance" {
  ami                  = data.aws_ami.amazon_linux.id
  instance_type        = "t3.micro"
  subnet_id            = module.data_vpc.private_subnet_ids[0]
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name
  vpc_security_group_ids = [aws_security_group.data_test_sg.id]

  tags = { Name = "Data-VPC-Test-Instance" }
}
# Route outbound internet traffic from App VPC to TGW
resource "aws_route" "app_default_to_tgw" {
  route_table_id         = module.app_vpc.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.central_tgw.id
}

# Route outbound internet traffic from Data VPC to TGW
resource "aws_route" "data_default_to_tgw" {
  route_table_id         = module.data_vpc.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.central_tgw.id
}
# --- GITHUB ACTIONS OIDC ROLE ---
module "github_oidc" {
  source             = "../../modules/github-oidc"
  github_org_or_user = "ccsawsdevops" # <--- Replace this
  github_repo        = "devops-lab1-multi-account"        # <--- Replace this
}

output "github_actions_role_arn" {
  value = module.github_oidc.role_arn
}
