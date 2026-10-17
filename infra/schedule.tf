resource "aws_cloudwatch_event_rule" "sync" {
  name                = "${var.name}-sync"
  schedule_expression = "rate(30 minutes)"
  state               = var.sync_schedule_enabled ? "ENABLED" : "DISABLED"
}

resource "aws_cloudwatch_event_target" "sync" {
  rule = aws_cloudwatch_event_rule.sync.name
  arn  = aws_lambda_function.sync.arn
}

resource "aws_lambda_permission" "sync_schedule" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sync.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sync.arn
}
