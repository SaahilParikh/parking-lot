data "archive_file" "zip_payload" {
  type        = "zip"
  source_file = "../../src/lambda_function_payload.js"
  output_path = var.function_code_output_path
}

# Create a DDB
resource "aws_dynamodb_table" "parking-lot-db" {
  name         = "parking-lot-items"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name               = "iam_for_lambda"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
  }
    EOF
}

resource "aws_iam_policy" "micro-service-function-policy" {
  name        = "micro-service-function-policy"
  description = "A policy for letting lambda functions interact with the dynamodb table."

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:DeleteItem",
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:Scan",
                "dynamodb:UpdateItem"
            ],
            "Resource": "${aws_dynamodb_table.parking-lot-db.arn}"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "table-policy-attach" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.micro-service-function-policy.arn
}

resource "aws_iam_role_policy_attachment" "basic-executor-attach" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "parking_lot_function" {

  function_name = var.function_name
  role          = aws_iam_role.iam_for_lambda.arn

  handler = "${var.handler_file_name}.handler"
  runtime = "nodejs16.x"

  filename         = data.archive_file.zip_payload.output_path
  source_code_hash = filebase64sha256(data.archive_file.zip_payload.output_path)

}

resource "aws_apigatewayv2_api" "parking_lot_api" {
  name          = "parking-lot-api"
  protocol_type = "HTTP"
}

resource aws_apigatewayv2_stage api_gw_stage {

  api_id = aws_apigatewayv2_api.parking_lot_api.id
  name = "$default"
  auto_deploy = true

}

resource aws_apigatewayv2_route api_routes {
  for_each = toset(var.routes)
  api_id    = aws_apigatewayv2_api.parking_lot_api.id

  route_key = each.key
  target = "integrations/${aws_apigatewayv2_integration.parking_lot_api_integration.id}"
}

resource aws_apigatewayv2_integration parking_lot_api_integration {
  api_id           = aws_apigatewayv2_api.parking_lot_api.id
  integration_type = "AWS_PROXY"

  payload_format_version = "2.0"

  description               = "API integration for parking lot routes"
  integration_method        = "POST"
  integration_uri           = aws_lambda_function.parking_lot_function.invoke_arn
}

resource "aws_lambda_permission" "allow_api" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.parking_lot_function.function_name
  principal     = "apigateway.amazonaws.com"
}

output parking_lot_baseurl {
  value = aws_apigatewayv2_stage.api_gw_stage.invoke_url
}