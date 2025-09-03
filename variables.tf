variable "project" {
  type = string
}

variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.80.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "desired" {
  type    = number
  default = 2
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 4
}

#Spot optional - default off (clean on demand)
variable "use_spot" {
  type    = bool
  default = false
}

variable "key_name" {
  type    = string
  default = null #only if for ssh
}