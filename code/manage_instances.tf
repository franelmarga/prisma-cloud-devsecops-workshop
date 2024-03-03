locals {
  start_cron           = try(var.env_vars["start_cron"],"cron(30 6 * * ? *)")
  stop_cron            = try(var.env_vars["stop_cron"],"cron(* 20 * * ? *)")
  deregister_amis_cron = try(var.env_vars["deregister_amis_cron"],"cron(0 0 ? * SUN *)")

  starter_lambda_path         = try(var.env_vars["starter_lambda_path"])
  stopper_lambda_path         = try(var.env_vars["stopper_lambda_path"])
  deregister_amis_lambda_path = try(var.env_vars["deregister_amis_lambda_path"])

}

module "lambda_working_hours" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 5.0"

  function_name = "lambda-working-hours"
  handler       = "start_instances.lambda_handler"
  runtime       = "python3.11"
  source_path   = local.starter_lambda_path
  timeout       = 30

  attach_policy_json = true
  policy_json = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:*",
          "autoscaling:*"
        ],
        "Resource" : "*"
      }
    ]
  })
}

module "lambda_sleeping_hours" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 5.0"

  function_name = "lambda-sleeping-hours"
  handler       = "stop_instances.lambda_handler"
  runtime       = "python3.11"
  source_path   = local.stopper_lambda_path
  timeout       = 30

  attach_policy_json = true
  policy_json = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:*",
          "autoscaling:*"
        ],
        "Resource" : "*"
      }
    ]
  })
}

module "eventbridge_schedules" {
  source  = "terraform-aws-modules/eventbridge/aws"
  version = "~> 2.0"

  create_bus  = false
  create_role = false

  rules = {
    start = {
      description         = "Start instances at specified time"
      schedule_expression = local.start_cron
    },
    stop = {
      description         = "Stop instances at specified time"
      schedule_expression = local.stop_cron
    },
    deregister_amis = {
      description         = "Deregister AMIs weekly"
      schedule_expression = local.deregister_amis_cron
    }
  }

  targets = {
    start = [
      {
        name = "StartInstances"
        arn  = module.lambda_working_hours.lambda_function_arn
      }
    ],
    stop = [
      {
        name = "StopInstances"
        arn  = module.lambda_sleeping_hours.lambda_function_arn
      }
    ],
    deregister_amis = [
      {
        name = "DeregisterAMIs"
        arn  = module.lambda_deregister_amis.lambda_function_arn
      }
    ]
  }
}
resource "aws_lambda_permission" "allow_eventbridge_to_start" {
  statement_id  = "AllowExecutionFromEventBridgeStart"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_working_hours.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = module.eventbridge_schedules.eventbridge_rule_arns["start"]
}

resource "aws_lambda_permission" "allow_eventbridge_to_stop" {
  statement_id  = "AllowExecutionFromEventBridgeStop"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_sleeping_hours.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = module.eventbridge_schedules.eventbridge_rule_arns["stop"]
}

resource "aws_lambda_permission" "allow_eventbridge_to_deregister_amis" {
  statement_id  = "AllowExecutionFromEventBridgeDeregisterAMIs"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_deregister_amis.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = module.eventbridge_schedules.eventbridge_rule_arns["deregister_amis"]
}

