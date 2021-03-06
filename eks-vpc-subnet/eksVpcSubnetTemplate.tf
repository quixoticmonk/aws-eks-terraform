terraform {
  required_version = "~> 0.12"
  experiments = [variable_validation]
}

provider "aws" {
    version = "~> 2.55"
    profile = "default"
    region = var.region
}

# -------------- Variables --------------
variable "vpcBlock" {
    type = string
    default = "192.168.0.0/16"
    description = "The CIDR range for the VPC. This should be a valid private (RFC 1918) CIDR range"

    # Example of validation block in case needed
    validation {
        condition = length(var.vpcBlock) > 4 && substr(var.vpcBlock, 0, 4) == "192."
        error_message = "Any error message ..."
    }
}

variable "publicSubnet01Block" {
    type = string
    default = "192.168.0.0/18"
    description = "CidrBlock for public subnet 01 within the VPC"
}

variable "publicSubnet02Block" {
    type = string
    default = "192.168.64.0/18"
    description = "CidrBlock for public subnet 02 within the VPC"
}

variable "privateSubnet01Block" {
    type = string
    default = "192.168.128.0/18"
    description = "CidrBlock for private subnet 01 within the VPC"
}

variable "privateSubnet02Block" {
    type = string
    default = "192.168.192.0/18"
    description = "CidrBlock for private subnet 02 within the VPC"
}

# -------------- Resources --------------
# -------------- VPC --------------
/*
VPC --> Internet Gateway {
    Subnet 1 (Public) --> Route Table (we need to associate it to each subnet) 
        --> Route (destination (CIDR inbound) --> target (Internet Gateway)) {
            EC2-1,
            EC2-2,
            LoadBalance
            NAT Gateway (it must be associate with a public subnet), which gives access to the internet from 
            private subnet. NAT Gateway will make a bridge between the private EC2 to the NAT Gateway
    }

    Subnet 2 (Private) --> Route Table (we need to associate it to each subnet)
        --> Route (destination (CIDR inbound) --> target (local)) {
            EC2-1,
            EC2-2,
            EC2-3,
    }
}

We first create the VPC --> Then we need to create/associate a Internet Gateway (IGW) to the VPC. 
Observe we can only have one IGW per VPC. The creation of the IGW doesn't guarantee you can access the EC2 inside 
your VPC/Subnet. We need to create a Route Table and a Route. The Route contains the CIDR (Inbound) and Target
*/
resource "aws_vpc" "eksVpc" {
    cidr_block = var.vpcBlock
    enable_dns_support = true
    enable_dns_hostnames = true

    tags = {
        Name = "eksVpc"
        Environment = "development"
    }
}

# -------------- Internet Gateway --------------
# Observe that there's no AWS VPCGatewayAttachment in Terraform. 
# The aws_internet_gateway resource will create the Internet Gateway and attach it to the specified VPC.
# That's make sense because there is only one internet gateway per VPC
resource "aws_internet_gateway" "eksVpcInternetGateway" {
    vpc_id = aws_vpc.eksVpc.id

    tags = {
        Name = "eksVpcInternetGateway"
    }
}

# -------------- Route Tables --------------
resource "aws_route_table" "publicRouteTable" {
    vpc_id = aws_vpc.eksVpc.id

    # route {
    #     cidr_block = var.publicBlock
    #     gateway_id = aws_internet_gateway.eksVpcInternetGateway.id
    # }

    # tags = {
    #     Name = "Public Subnets"
    #     Network = "Public"
    # }
}

resource "aws_route_table" "privateRouteTable01" {
    vpc_id = aws_vpc.eksVpc.id

    tags = {
        Name = "Private Subnet AZ1"
        Network = "Private 01"
    }
}

resource "aws_route_table" "privateRouteTable02" {
    vpc_id = aws_vpc.eksVpc.id

    tags = {
        Name = "Private Subnet AZ2"
        Network = "Private 02"
    }
}

# -------------- Routes --------------
resource "aws_route" "publicRoute" {
    route_table_id = aws_route_table.publicRouteTable.id
    destination_cidr_block  = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eksVpcInternetGateway.id
}

resource "aws_route" "privateRoute01" {
    route_table_id = aws_route_table.privateRouteTable01.id
    destination_cidr_block  = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.natGateway01.id
}

resource "aws_route" "privateRoute02" {
    route_table_id = aws_route_table.privateRouteTable02.id
    destination_cidr_block  = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.natGateway02.id
}

# -------------- Nat Gateways --------------
resource "aws_nat_gateway" "natGateway01" {
    allocation_id = aws_eip.natGatewayEIP1.id
    subnet_id = aws_subnet.publicSubnet01.id
}

resource "aws_nat_gateway" "natGateway02" {
    allocation_id = aws_eip.natGatewayEIP2.id
    subnet_id = aws_subnet.publicSubnet02.id
}

# -------------- EIP --------------
resource "aws_eip" "natGatewayEIP1" {
    vpc = true
}

resource "aws_eip" "natGatewayEIP2" {
    vpc = true
}

# -------------- Subnets --------------
resource "aws_subnet" "publicSubnet01" {
    vpc_id = aws_vpc.eksVpc.id
    cidr_block = var.publicSubnet01Block
    map_public_ip_on_launch = true
    # availability_zone = 

    tags = {
        Name = "publicSubnet01"
    }
}

resource "aws_subnet" "publicSubnet02" {
    vpc_id = aws_vpc.eksVpc.id
    cidr_block = var.publicSubnet02Block
    map_public_ip_on_launch = true
    # availability_zone = 

    tags = {
        Name = "publicSubnet02"
    }
}

resource "aws_subnet" "privateSubnet01" {
    vpc_id = aws_vpc.eksVpc.id
    cidr_block = var.privateSubnet01Block
    # availability_zone = 

    tags = {
        Name = "privateSubnet01"
    }
}

resource "aws_subnet" "privateSubnet02" {
    vpc_id = aws_vpc.eksVpc.id
    cidr_block = var.privateSubnet02Block
    # availability_zone = 

    tags = {
        Name = "privateSubnet02"
    }
}

# -------------- Subnet/Route Table Association --------------
resource "aws_route_table_association" "publicSubnet01RouteTableAssociation" {
  subnet_id      = aws_subnet.publicSubnet01.id
  route_table_id = aws_route_table.publicRouteTable.id
}

resource "aws_route_table_association" "publicSubnet02RouteTableAssociation" {
  subnet_id      = aws_subnet.publicSubnet02.id
  route_table_id = aws_route_table.publicRouteTable.id
}

resource "aws_route_table_association" "privateSubnet01RouteTableAssociation" {
  subnet_id      = aws_subnet.privateSubnet01.id
  route_table_id = aws_route_table.privateRouteTable01.id
}

resource "aws_route_table_association" "privateSubnet02RouteTableAssociation" {
  subnet_id      = aws_subnet.privateSubnet02.id
  route_table_id = aws_route_table.privateRouteTable02.id
}

# -------------- Security Group --------------
resource "aws_security_group" "allow_tls" {
    name = "vpcSecurityGroup"
    description = "Cluster communication with worker nodes"
    vpc_id = aws_vpc.eksVpc.id
}

# -------------- Outputs --------------
