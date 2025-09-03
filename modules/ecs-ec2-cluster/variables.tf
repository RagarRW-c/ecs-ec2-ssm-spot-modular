variable "project"{
    type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnets" {
  type = list(string)
}

variable "instance_type" {
  type = string
}

variable "desired" {
  type = number
}

variable "min_size" {
  type = number
}

variable "max_size" {
  type = number
}

variable "key_name" {
  type = string
  default = null
}

variable "use_spot" {
  type = bool
  default = false
}

variable "tags" {
  type = map(string)
  default = {
    
  }
}