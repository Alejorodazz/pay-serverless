import base64
import hashlib
import hmac
import json
import os
import time
from datetime import datetime, timezone

import boto3

from idempotency import claim, complete, release, request_hash


secrets_manager = boto3.client("secretsmanager")
sqs = boto3.client("sqs")
dynamodb = boto3.resource("dynamodb")


def _get_webhook_secret():
    secret_arn = os.getenv("RECURRENTE_WEBHOOK_SECRET_ARN", "")
    if not secret_arn:
        raise RuntimeError("RECURRENTE_WEBHOOK_SECRET_ARN no está configurada")

    response = secrets_manager.get_secret_value(SecretId=secret_arn)
    secret = response.get("SecretString", "")

    try:
        secret_data = json.loads(secret)
    except json.JSONDecodeError:
        return secret

    for key in ("signing_secret", "signingSecret", "webhook_secret", "secret"):
        if secret_data.get(key):
            return secret_data[key]

    raise ValueError("El secreto de webhook de Recurrente no contiene una llave conocida")


def _header(headers, name):
    for key, value in (headers or {}).items():
        if key.lower() == name.lower():
            return value
    return ""


def _verify_signature(raw_body, headers, secret):
    message_id = _header(headers, "svix-id")
    timestamp = _header(headers, "svix-timestamp")
    signatures = _header(headers, "svix-signature")

    if not message_id or not timestamp or not signatures:
        return False

    try:
        timestamp_value = int(timestamp)
    except ValueError:
        return False

    if abs(int(time.time()) - timestamp_value) > 300:
        return False

    if not secret.startswith("whsec_"):
        return False

    secret_bytes = base64.b64decode(secret.split("_", 1)[1])
    signed_content = f"{message_id}.{timestamp}.{raw_body}".encode("utf-8")
    expected = base64.b64encode(
        hmac.new(secret_bytes, signed_content, hashlib.sha256).digest()
    ).decode("utf-8")

    return any(
        hmac.compare_digest(value.split(",", 1)[1], expected)
        for value in signatures.split(" ")
        if value.startswith("v1,")
    )


def _queue_failed(raw_body, reason):
    queue_url = os.getenv("FAILED_QUEUE_URL", "")
    if queue_url:
        sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps({"reason": reason, "raw_body": raw_body}),
        )


def _save_payment_state(payload):
    table_name = os.getenv("PAYMENT_TABLE_NAME", "")
    payment = payload.get("payment") or {}
    checkout = payload.get("checkout") or {}
    payment_id = payment.get("id") or checkout.get("id") or payload.get("id")

    if table_name and payment_id:
        dynamodb.Table(table_name).put_item(
            Item={
                "payment_id": payment_id,
                "status": payload.get("status", "unknown"),
                "event_type": payload.get("event_type", "unknown"),
                "updated_at": datetime.now(timezone.utc).isoformat(),
                "payload": json.dumps(payload),
            }
        )


def payment_webhook(event, context):
    raw_body = "{}"
    try:
        raw_body = event.get("body") or "{}"
        if event.get("isBase64Encoded"):
            raw_body = base64.b64decode(raw_body).decode("utf-8")

        headers = event.get("headers") or {}
        if not _verify_signature(raw_body, headers, _get_webhook_secret()):
            _queue_failed(raw_body, "invalid_recurrente_signature")
            return {"statusCode": 401, "body": json.dumps({"error": "Invalid signature"})}

        event_id = _header(headers, "svix-id")
        payload = json.loads(raw_body)
        payload_hash = request_hash(raw_body)
        storage_key = f"webhook:{event_id}"
        idempotency = claim(storage_key, payload_hash)
        if idempotency["state"] == "CONFLICT":
            return {
                "statusCode": 409,
                "body": json.dumps({"error": "Webhook ID was reused with a different body"}),
            }
        if idempotency["state"] == "IN_PROGRESS":
            return {
                "statusCode": 409,
                "headers": {"Retry-After": "2"},
                "body": json.dumps({"error": "Webhook is already being processed"}),
            }
        if idempotency["state"] == "COMPLETED":
            return {
                "statusCode": 200,
                "body": json.dumps({"received": True, "duplicate": True}),
            }

        _save_payment_state(payload)

        valid_queue_url = os.getenv("VALID_QUEUE_URL", "")
        if valid_queue_url:
            sqs.send_message(
                QueueUrl=valid_queue_url,
                MessageBody=raw_body,
                MessageAttributes={
                    "event_id": {"DataType": "String", "StringValue": event_id}
                },
            )

        complete(storage_key, payload_hash)

        return {"statusCode": 200, "body": json.dumps({"received": True})}
    except Exception as error:
        if "payload_hash" in locals() and "storage_key" in locals():
            release(storage_key, payload_hash)
        _queue_failed(raw_body, str(error))
        return {"statusCode": 500, "body": json.dumps({"error": "Webhook processing failed"})}
