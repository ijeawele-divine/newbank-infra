variable "region" {
  type = string
}

variable "project_name" {
  description = "Name of the project used for resource naming"
  type = string
}

variable "environment" {
  description = "Deployment environment (prod, staging, dev)"
  type = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type = list(string)
}

variable "public_subnet_cidrs" {
  description = "List of public subnet CIDRs, one per AZ"
  type = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of private subnet CIDRs, one per AZ"
  type = list(string)
}

variable "data_subnet_cidrs" {
  description = "List of data subnet CIDRs, one per AZ"
  type = list(string)
}