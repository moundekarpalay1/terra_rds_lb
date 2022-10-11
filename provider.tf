provider "aws" {
  region     = "ap-south-1"
  access_key = "AKIAQOYVVZDBD7RXMQPP"
  secret_key = "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"
}

## VPC for APP

resource "aws_vpc" "dac_app_vpc" {
  cidr_block           = "10.128.0.0/16"

  tags = {
    Name = "dac_app_vpc"
  }
}
## VPC for DB

resource "aws_vpc" "dac_db_vpc" {
  cidr_block           = "10.240.0.0/16"
  
  tags = {
    Name = "dac_db_vpc"
  }
}

## Subnet for APP

resource "aws_subnet" "dac_app_subnet" {
  vpc_id            = aws_vpc.dac_app_vpc.id
  cidr_block        = "10.128.0.0/17"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "dac_app_subnet"
  }
}

## Subnet for DB

resource "aws_subnet" "dac_db_subnet_1" {
  vpc_id            = aws_vpc.dac_db_vpc.id
  cidr_block        = "10.240.0.0/17"
  availability_zone = "ap-south-1b"

  tags = {
    Name = "dac_db_subnet_1"
  }
}

resource "aws_subnet" "dac_db_subnet_2" {
  vpc_id            = aws_vpc.dac_db_vpc.id
  cidr_block        = "10.240.128.0/17"
  availability_zone = "ap-south-1c"

  tags = {
    Name = "dac_db_subnet_2"
  }
}

## Internet Gateway for APP

resource "aws_internet_gateway" "dac_app_igw" {
  vpc_id = aws_vpc.dac_app_vpc.id

  tags = {
    Name = "dac_app_igw"
  }
}

### VPC PEERING SECTION

## Peering connection between dac_app_vpc and dac_db_vpc

resource "aws_vpc_peering_connection" "dac_app_db_peering" {
  peer_vpc_id   = aws_vpc.dac_db_vpc.id
  vpc_id        = aws_vpc.dac_app_vpc.id
  auto_accept   = true

  tags = {
    Name = "dac_vpc_app_db_peering"
  }
}

## Route for APP

resource "aws_route_table" "dac_app_rt" {
  vpc_id = aws_vpc.dac_app_vpc.id

  route {
    cidr_block                = "10.240.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.dac_app_db_peering.id
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dac_app_igw.id
  }

  tags = {
    Name = "dac_app_rt"
  }
}

## Route for DB

resource "aws_route_table" "dac_db_rt" {
  vpc_id = aws_vpc.dac_db_vpc.id

  route {
    cidr_block                = "10.128.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.dac_app_db_peering.id
  }

  tags = {
    Name = "dac_db_rt"
  }
}

## Route Table - Subnet Associations

resource "aws_route_table_association" "dac_app_rta" {
  subnet_id      = aws_subnet.dac_app_subnet.id
  route_table_id = aws_route_table.dac_app_rt.id
}

resource "aws_route_table_association" "dac_db_rta1" {
  subnet_id      = aws_subnet.dac_db_subnet_1.id
  route_table_id = aws_route_table.dac_db_rt.id
}

resource "aws_route_table_association" "dac_db_rta2" {
  subnet_id      = aws_subnet.dac_db_subnet_2.id
  route_table_id = aws_route_table.dac_db_rt.id
}

## SG for APP VPC

resource "aws_security_group" "dac_app_sg" {
  name = "dac_app_sg"
  description = "EC2 instances security group"
  vpc_id      = aws_vpc.dac_app_vpc.id
  

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    description = "Allow HTTP traffic"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    description = "Allow HTTPS traffic"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "dac_app_sg"
  }
}

## SG for DB VPC

resource "aws_security_group" "dac_db_sg" {
  name = "dac_db_sg"
  description = "EC2 instances security group"
  vpc_id      = aws_vpc.dac_db_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    description = "Allow traffic to MySQL"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "dac_db_sg"
  }
}
resource "aws_instance" "dac_app" {
  count                         = 3
  ami                           = "ami-01216e7612243e0ef"
  instance_type                 = "t2.micro"
  key_name                      = "testpem"
  vpc_security_group_ids        = [aws_security_group.dac_app_sg.id]
  subnet_id                     = aws_subnet.dac_app_subnet.id
  associate_public_ip_address   = "true"

  tags = {
    Name = "dac_app_${count.index}"
  }
}



resource "aws_lb" "dac_app_lb" {
  name               = "dac-app-lb"
  internal           = false
  load_balancer_type = "network"
  subnets            = aws_subnet.dac_app_subnet.*.id

  tags = {
    Environment = "dev"
  }
}

## LB Target Group

resource "aws_lb_target_group" "dac_app_tgp" {
  name     = "dac-app-tgp"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.dac_app_vpc.id
}

## LB Targets Registration

resource "aws_lb_target_group_attachment" "dac_app_tgpa" {
  count            = length(aws_instance.dac_app)
  target_group_arn = aws_lb_target_group.dac_app_tgp.arn
  target_id        = aws_instance.dac_app[count.index].id
  port             = 80
}

## LB Listener

resource "aws_lb_listener" "dac_app_lb_listener" {
  load_balancer_arn = aws_lb.dac_app_lb.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dac_app_tgp.arn
  }
}

## DB Subent Group

resource "aws_db_subnet_group" "dac_db_subnet_group" {
  name       = "dac_db_subnet_group"
  subnet_ids = [aws_subnet.dac_db_subnet_1.id, aws_subnet.dac_db_subnet_2.id]

  tags = {
    Name = "dac_db_subnet_group"
  }
}

## DB instance

resource "aws_db_instance" "dac_db" {
  allocated_storage       = 20
  storage_type            = "gp2"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t2.micro"
  name                    = "mydb"
  identifier              = "dacdb"
  username                = "admin"
  password                = "info9999"
  parameter_group_name    = "default.mysql8.0"
  db_subnet_group_name    = aws_db_subnet_group.dac_db_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.dac_db_sg.id]
  skip_final_snapshot     = "true"
}

