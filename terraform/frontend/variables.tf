variable "domain_name" {
  type = string
  default = "saahil.io"
  description = "Also doubles as the name of the bucket without the www. prefix."
}

variable "www_domain_name" {
  type = string
  default = "www.saahil.io"
  description = "Also doubles as the name of the bucket with the www. prefix."
}