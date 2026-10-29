import json
import math
import os
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import boto3

from idempotency import claim, complete, release, request_hash


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


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def _header(headers, name):
    for key, value in (headers or {}).items():
        if key.lower() == name.lower():
            return value
    return ""


def create_checkout_handler(event, context):
    idempotency_key = _header(event.get("headers"), "Idempotency-Key")
    try:
        body = json.loads(event.get("body") or "{}")
        idempotency_key = idempotency_key or body.get("idempotency_key", "")
        if not idempotency_key or not isinstance(idempotency_key, str):
            return _response(400, {"error": "Idempotency-Key header is required."})
        if len(idempotency_key) > 255:
            return _response(400, {"error": "Idempotency-Key is too long."})

        amount = body.get("amount")

        if amount is None or not math.isfinite(float(amount)) or float(amount) <= 0:
            return _response(400, {"error": "Invalid amount provided."})

        quantity = int(body.get("quantity", 1))
        if quantity < 1:
            return _response(400, {"error": "Invalid quantity provided."})

        currency = body.get("currency", os.getenv("DEFAULT_CURRENCY", "USD"))
        item = {
            "name": body.get("product_name", os.getenv("PRODUCT_NAME", "Payment")),
            "amount_in_cents": round(float(amount) * 100),
            "currency": currency,
            "quantity": quantity,
        }

        payload = {
            "items": body.get("items", [item]),
            "success_url": body.get(
                "success_url", os.getenv("RECURRENTE_SUCCESS_URL", "")
            ),
            "cancel_url": body.get(
                "cancel_url", os.getenv("RECURRENTE_CANCEL_URL", "")
            ),
        }

        payload_hash = request_hash(payload)
        storage_key = f"checkout:{idempotency_key}"
        idempotency = claim(storage_key, payload_hash)
        if idempotency["state"] == "CONFLICT":
            return _response(
                409,
                {"error": "Idempotency-Key was already used with a different request."},
            )
        if idempotency["state"] == "IN_PROGRESS":
            response = _response(409, {"error": "Request with this key is in progress."})
            response["headers"]["Retry-After"] = "2"
            return response
        if idempotency["state"] == "COMPLETED":
            response = _response(idempotency["status_code"], idempotency["body"])
            response["headers"]["Idempotent-Replay"] = "true"
            return response

        api_base_url = os.getenv(
            "RECURRENTE_API_BASE_URL", "https://app.recurrente.com/api"
        ).rstrip("/")
        request = Request(
            f"{api_base_url}/checkouts",
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "X-SECRET-KEY": _get_recurrente_secret(),
                "Idempotency-Key": idempotency_key,
            },
            method="POST",
        )

        with urlopen(request, timeout=15) as response:
            recurrente_response = json.loads(response.read().decode("utf-8"))

        response_body = {
            "checkout_id": recurrente_response.get("id"),
            "checkout_url": recurrente_response.get("checkout_url"),
        }
        complete(storage_key, payload_hash, 201, response_body)
        return _response(201, response_body)
    except (HTTPError, URLError) as error:
        if "payload_hash" in locals() and "storage_key" in locals():
            release(storage_key, payload_hash)
        return _response(502, {"error": "Recurrente request failed", "detail": str(error)})
    except (ValueError, TypeError, json.JSONDecodeError) as error:
        if "payload_hash" in locals() and "storage_key" in locals():
            release(storage_key, payload_hash)
        return _response(400, {"error": str(error)})
    except Exception as error:
        if "payload_hash" in locals() and "storage_key" in locals():
            release(storage_key, payload_hash)
        return _response(500, {"error": "Internal server error", "detail": str(error)})
