variable "project_name" {
  description = "Nombre base usado para nombrar los recursos del gateway."
  type        = string
  default     = "pay-gateway-serverless"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name solo puede contener letras minúsculas, números y guiones."
  }
}

variable "environment" {
  description = "Ambiente de despliegue."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "environment solo puede contener letras minúsculas, números y guiones."
  }
}

variable "aws_region" {
  description = "Región AWS donde se despliega la infraestructura."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Perfil AWS opcional. Si es null se usa la cadena de credenciales estándar de AWS."
  type        = string
  default     = null
  nullable    = true
}

variable "frontend_bucket" {
  description = "Nombre opcional del bucket S3 del frontend. Si se omite se genera uno basado en la cuenta."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.frontend_bucket == null || can(regex(
      "^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$",
      var.frontend_bucket,
    ))
    error_message = "frontend_bucket debe ser un nombre S3 válido, en minúsculas y sin guiones bajos."
  }
}

variable "bucket_tags" {
  description = "Tags adicionales para el bucket del frontend."
  type        = map(string)
  default     = {}
}

variable "frontend_domain_name" {
  description = "Dominio opcional del frontend, por ejemplo app.apisys.info. Requiere certificado ACM en us-east-1."
  type        = string
  default     = null
  nullable    = true
}

variable "api_custom_domain_name" {
  description = "Dominio opcional de API, por ejemplo payment.apisys.info."
  type        = string
  default     = null
  nullable    = true
}

variable "api_certificate_arn" {
  description = "ARN opcional del certificado ACM regional para el dominio de API."
  type        = string
  default     = null
  nullable    = true
}

variable "cloudflare_zone_id" {
  description = "ID de la zona Cloudflare que contiene los dominios del frontend y la API."
  type        = string
  default     = null
  nullable    = true
}

variable "cloudflare_api_token" {
  description = "Token API de Cloudflare con permisos DNS edit para la zona indicada."
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "recurrente_secret_arn" {
  description = "ARN opcional del secreto API de Recurrente consumido por las Lambdas."
  type        = string
  default     = null
  nullable    = true
}

variable "recurrente_webhook_secret_arn" {
  description = "ARN opcional del signing secret de webhooks de Recurrente."
  type        = string
  default     = null
  nullable    = true
}

variable "recurrente_api_base_url" {
  description = "URL base de la API de Recurrente."
  type        = string
  default     = "https://app.recurrente.com/api"
}

variable "recurrente_success_url" {
  description = "URL de retorno después de un checkout exitoso."
  type        = string
  default     = "https://example.com/success"
}

variable "recurrente_cancel_url" {
  description = "URL de retorno cuando el checkout es cancelado."
  type        = string
  default     = "https://example.com/cancel"
}

variable "checkout_default_currency" {
  description = "Moneda usada por checkout cuando el request no la especifica."
  type        = string
  default     = "USD"

  validation {
    condition     = can(regex("^[A-Z]{3}$", var.checkout_default_currency))
    error_message = "checkout_default_currency debe ser un código ISO 4217 de tres letras mayúsculas."
  }
}

variable "checkout_product_name" {
  description = "Nombre de producto enviado al proveedor de pagos."
  type        = string
  default     = "Payment"
}

variable "cors_allow_origin" {
  description = "Origen permitido por CORS. Si se omite, se usa el dominio del frontend o *."
  type        = string
  default     = null
  nullable    = true
}

variable "laravel_api_base_url" {
  description = "URL base de la API Laravel que recibe la activación recurrente."
  type        = string
  default     = null
  nullable    = true
}

variable "laravel_api_provision_path" {
  description = "Ruta POST de Laravel que recibe el evento de activación del tenant."
  type        = string
  default     = "/api/tenants/provision"
}

variable "laravel_api_token_secret_arn" {
  description = "ARN opcional del secreto con el token de la API Laravel."
  type        = string
  default     = null
  nullable    = true
}

variable "lambda_log_retention_days" {
  description = "Días de retención de logs de las Lambdas."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.lambda_log_retention_days)
    error_message = "lambda_log_retention_days debe ser un período válido de CloudWatch Logs."
  }
}

variable "event_batch_size" {
  description = "Cantidad máxima de eventos recurrentes por invocación."
  type        = number
  default     = 10

  validation {
    condition     = var.event_batch_size >= 1 && var.event_batch_size <= 10
    error_message = "event_batch_size debe estar entre 1 y 10."
  }
}

variable "event_max_batching_window_seconds" {
  description = "Ventana máxima de agrupación de eventos SQS."
  type        = number
  default     = 5

  validation {
    condition     = var.event_max_batching_window_seconds >= 0 && var.event_max_batching_window_seconds <= 300
    error_message = "event_max_batching_window_seconds debe estar entre 0 y 300."
  }
}
