import json
import os
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import boto3

from idempotency import claim, complete, release, request_hash


secrets_manager = boto3.client("secretsmanager")


def _get_laravel_token():
    secret_arn = os.getenv("LARAVEL_API_TOKEN_SECRET_ARN", "")
    if not secret_arn:
        return os.getenv("LARAVEL_API_TOKEN", "")

    secret = secrets_manager.get_secret_value(SecretId=secret_arn).get("SecretString", "")
    try:
        secret_data = json.loads(secret)
    except json.JSONDecodeError:
        return secret

    for key in ("token", "api_token", "laravel_api_token", "secret"):
        if secret_data.get(key):
            return secret_data[key]
    raise ValueError("El secreto de Laravel no contiene un token conocido")


def _event_id(record, payload):
    attributes = record.get("messageAttributes") or {}
    event_attribute = attributes.get("event_id") or {}
    return (
        event_attribute.get("stringValue")
        or event_attribute.get("StringValue")
        or payload.get("event_id")
        or payload.get("id")
        or record.get("messageId")
    )


def _provision(record):
    raw_body = record.get("body") or "{}"
    payload = json.loads(raw_body)
    event_id = _event_id(record, payload)
    if not event_id:
        raise ValueError("El evento no contiene un identificador estable")

    key = f"tenant-provision:{event_id}"
    payload_hash = request_hash(raw_body)
    state = claim(key, payload_hash)
    if state == "COMPLETED":
        return
    if state == "IN_PROGRESS":
        raise RuntimeError("El evento ya está siendo procesado")
    if state == "CONFLICT":
        raise ValueError("El identificador del evento fue reutilizado con otro payload")

    try:
        base_url = os.getenv("LARAVEL_API_BASE_URL", "").rstrip("/")
        path = os.getenv("LARAVEL_API_PROVISION_PATH", "/api/tenants/provision")
        if not base_url:
            raise RuntimeError("LARAVEL_API_BASE_URL no está configurada")

        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-Idempotency-Key": event_id,
        }
        token = _get_laravel_token()
        if token:
            headers["Authorization"] = f"Bearer {token}"

        request = Request(
            f"{base_url}/{path.lstrip('/')}",
            data=raw_body.encode("utf-8"),
            headers=headers,
            method="POST",
        )
        with urlopen(request, timeout=30) as response:
            if response.status < 200 or response.status >= 300:
                raise RuntimeError(f"Laravel respondió con HTTP {response.status}")

        complete(key, payload_hash)
    except Exception:
        release(key, payload_hash)
        raise


def provision_tenant(event, context):
    failures = []
    for record in event.get("Records", []):
        try:
            _provision(record)
        except (HTTPError, URLError, json.JSONDecodeError, RuntimeError, ValueError):
            failures.append({"itemIdentifier": record.get("messageId", "")})
        except Exception:
            failures.append({"itemIdentifier": record.get("messageId", "")})

    return {"batchItemFailures": [failure for failure in failures if failure["itemIdentifier"]]}
