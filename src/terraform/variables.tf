variable "project_name" {
  default = "parking-lot"
}

variable "handler_file_name" {
  default = "lambda_function_payload"
}

variable "function_code_output_path" {
  default = "../target/lambda_function_payload.zip"
}

variable "function_code_src_path" {
  default = "../backend/lambda_function_payload.js"
}

variable "frontend_src_path" {
  default = "../frontend/parking-lot"
}


variable "routes" {
  default = ["PUT /v1/items", "DELETE /v1/items/{id}", "GET /v1/items"]
}

variable "domain_name" {
  default = "todolot.com"
  description = "Also doubles as the name of the bucket without the www. prefix."
}

variable "api_domain_name" {
  default = "api.todolot.com"
}

variable "www_domain_name" {
  default = "www.todolot.com"
}




