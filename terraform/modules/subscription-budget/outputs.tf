output "id" {
  description = "Resource ID of the budget."
  value       = azurerm_consumption_budget_subscription.this.id
}

output "thresholds" {
  description = "The configured alert thresholds, for reporting and for tests."
  value = {
    actual     = var.actual_threshold_percent
    forecasted = var.forecast_threshold_percent
  }
}
