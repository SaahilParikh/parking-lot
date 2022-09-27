variable "function_name" {
  default = "parking-lot-function"
}

variable "handler_file_name" {
  default = "lambda_function_payload"
}

variable "function_code_output_path" {
  default = "../../target/lambda_function_payload.zip"
}

variable "routes" {
  default = ["GET /items/{id}", "PUT /items", "DELETE /items/{id}", "GET /items"]
}

variable "domain_name" {
  default = "saahil.io"
}

variable "api_domain_name" {
  default = "api.saahil.io"
}

variable "www_domain_name" {
  default = "www.saahil.io"
}