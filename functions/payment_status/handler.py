import json
import os
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import boto3


secrets_manager = boto3.client("secretsmanager")


def _get_recurrente_secret():
    secret_arn = os.getenv("RECURRENTE_SECRET_ARN", "")
    if not secret_arn:
        raise RuntimeError("RECURRENTE_SECRET_ARN no está configurada")

    response = secrets_manager.get_secret_value(SecretId=secret_arn)
    secret = response.get("SecretString", "")

    try:
        secret_data = json.loads(secret)
    except json.JSONDecodeError:
        return secret

    for key in ("secret_key", "api_key", "recurrente_secret_key", "key"):
        if secret_data.get(key):
            return secret_data[key]

    raise ValueError("El secreto de Recurrente no contiene una llave conocida")


def payment_status(event, context):
    query = event.get("queryStringParameters") or {}
    path = event.get("pathParameters") or {}
    checkout_id = query.get("checkout_id") or query.get("id") or path.get("checkout_id")

    if not checkout_id:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "checkout_id is required"}),
        }

    try:
        api_base_url = os.getenv(
            "RECURRENTE_API_BASE_URL", "https://app.recurrente.com/api"
        ).rstrip("/")
        request = Request(
            f"{api_base_url}/checkouts/{checkout_id}",
            headers={"X-SECRET-KEY": _get_recurrente_secret()},
            method="GET",
        )

        with urlopen(request, timeout=15) as response:
            payload = json.loads(response.read().decode("utf-8"))

        return {"statusCode": 200, "body": json.dumps(payload)}
    except (HTTPError, URLError) as error:
        return {
            "statusCode": 502,
            "body": json.dumps({"error": "Recurrente request failed", "detail": str(error)}),
        }
    except Exception as error:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Internal server error", "detail": str(error)}),
        }
