resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.env}-vpc" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_a_cidr
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = { Name = "${var.env}-public-subnet-a" }
}

resource "aws_subnet" "public_c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_c_cidr
  availability_zone       = "${var.region}c"
  map_public_ip_on_launch = true

  tags = { Name = "${var.env}-public-subnet-c" }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_a_cidr
  availability_zone = "${var.region}a"

  tags = { Name = "${var.env}-private-subnet-a" }
}

resource "aws_subnet" "private_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_c_cidr
  availability_zone = "${var.region}c"

  tags = { Name = "${var.env}-private-subnet-c" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.env}-igw" }
}

# NAT Gateway(s)
resource "aws_eip" "nat_a" {
  domain = "vpc"
  tags   = { Name = "${var.env}-nat-eip-a" }
}

resource "aws_nat_gateway" "a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.public_a.id

  tags = { Name = "${var.env}-nat-a" }
}

resource "aws_eip" "nat_c" {
  count  = var.enable_multi_nat ? 1 : 0
  domain = "vpc"
  tags   = { Name = "${var.env}-nat-eip-c" }
}

resource "aws_nat_gateway" "c" {
  count         = var.enable_multi_nat ? 1 : 0
  allocation_id = aws_eip.nat_c[0].id
  subnet_id     = aws_subnet.public_c.id

  tags = { Name = "${var.env}-nat-c" }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.env}-public-rt" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_c" {
  subnet_id      = aws_subnet.public_c.id
  route_table_id = aws_route_table.public.id
}

# Private Route Tables
resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.a.id
  }

  tags = { Name = "${var.env}-private-rt-a" }
}

resource "aws_route_table" "private_c" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.enable_multi_nat ? aws_nat_gateway.c[0].id : aws_nat_gateway.a.id
  }

  tags = { Name = "${var.env}-private-rt-c" }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "private_c" {
  subnet_id      = aws_subnet.private_c.id
  route_table_id = aws_route_table.private_c.id
}

# VPN Client (Dev only)
resource "aws_ec2_client_vpn_endpoint" "main" {
  count                  = var.enable_vpn ? 1 : 0
  client_cidr_block      = "10.100.0.0/16"
  server_certificate_arn = var.vpn_server_cert_arn
  split_tunnel           = true

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = var.vpn_client_cert_arn
  }

  connection_log_options {
    enabled = false
  }

  tags = { Name = "${var.env}-vpn-client" }
}

resource "aws_ec2_client_vpn_network_association" "public_a" {
  count                  = var.enable_vpn ? 1 : 0
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main[0].id
  subnet_id              = aws_subnet.public_a.id
}

resource "aws_ec2_client_vpn_authorization_rule" "all" {
  count                  = var.enable_vpn ? 1 : 0
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main[0].id
  target_network_cidr    = aws_vpc.main.cidr_block
  authorize_all_groups   = true
}
