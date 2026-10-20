resource "aws_cloudwatch_event_rule" "sync" {
  name                = "${var.name}-sync"
  schedule_expression = "rate(30 minutes)"
  state               = var.schedule_enabled ? "ENABLED" : "DISABLED"
}

resource "aws_cloudwatch_event_target" "sync" {
  count = local.deploy
  rule  = aws_cloudwatch_event_rule.sync.name
  arn   = aws_lambda_function.sync[0].arn
}

resource "aws_lambda_permission" "sync_schedule" {
  count         = local.deploy
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sync[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sync.arn
}
