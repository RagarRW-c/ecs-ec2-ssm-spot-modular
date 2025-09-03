variable "project" {
  type = string
}

variable "cluster_arn" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "cp_name" {
  type = string
}

variable "private_subnets" {
  type = list(string)
}

variable "vpc_id" {
  type = string
}

variable "alb_tg_arn" {
  type = string
}

variable "alb_sg_id" {
  type = string
}

variable "region" {
  type = string
}

variable "secret_arn" {
  type = string
}

variable "tags" {
  type = map(string)
  default = {}
}

