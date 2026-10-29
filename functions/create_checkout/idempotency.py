import hashlib
import json
import os
import time

import boto3
from botocore.exceptions import ClientError


dynamodb = boto3.resource("dynamodb")


def request_hash(payload):
    canonical_payload = json.dumps(
        payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    )
    return hashlib.sha256(canonical_payload.encode("utf-8")).hexdigest()


def _table():
    table_name = os.getenv("IDEMPOTENCY_TABLE_NAME", "")
    if not table_name:
        raise RuntimeError("IDEMPOTENCY_TABLE_NAME no está configurada")
    return dynamodb.Table(table_name)


def claim(key, payload_hash):
    """Claim a key, replay a completed response, or report an active claim."""
    table = _table()
    now = int(time.time())
    ttl = int(os.getenv("IDEMPOTENCY_TTL_SECONDS", "604800"))
    lock_ttl = int(os.getenv("IDEMPOTENCY_LOCK_TTL_SECONDS", "120"))
    item = {
        "idempotency_key": key,
        "request_hash": payload_hash,
        "status": "IN_PROGRESS",
        "lock_expires_at": now + lock_ttl,
        "expires_at": now + ttl,
        "updated_at": now,
    }

    try:
        table.put_item(Item=item, ConditionExpression="attribute_not_exists(idempotency_key)")
        return {"state": "CLAIMED"}
    except ClientError as error:
        if error.response.get("Error", {}).get("Code") != "ConditionalCheckFailedException":
            raise

    existing = table.get_item(Key={"idempotency_key": key}, ConsistentRead=True).get("Item")
    if not existing:
        return claim(key, payload_hash)
    if existing.get("request_hash") != payload_hash:
        return {"state": "CONFLICT"}
    if existing.get("status") == "COMPLETED":
        return {
            "state": "COMPLETED",
            "status_code": int(existing.get("response_status", 200)),
            "body": json.loads(existing.get("response_body", "{}")),
        }
    if int(existing.get("lock_expires_at", 0)) > now:
        return {"state": "IN_PROGRESS"}

    try:
        table.update_item(
            Key={"idempotency_key": key},
            UpdateExpression=(
                "SET #status = :in_progress, lock_expires_at = :lock_expires_at, "
                "updated_at = :updated_at"
            ),
            ConditionExpression=(
                "request_hash = :request_hash AND #status = :in_progress "
                "AND lock_expires_at <= :now"
            ),
            ExpressionAttributeNames={"#status": "status"},
            ExpressionAttributeValues={
                ":in_progress": "IN_PROGRESS",
                ":lock_expires_at": now + lock_ttl,
                ":updated_at": now,
                ":request_hash": payload_hash,
                ":now": now,
            },
        )
        return {"state": "CLAIMED"}
    except ClientError as error:
        if error.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
            return {"state": "IN_PROGRESS"}
        raise


def complete(key, payload_hash, status_code, body):
    _table().update_item(
        Key={"idempotency_key": key},
        UpdateExpression=(
            "SET #status = :completed, response_status = :status_code, "
            "response_body = :body, updated_at = :updated_at"
        ),
        ConditionExpression="request_hash = :request_hash AND #status = :in_progress",
        ExpressionAttributeNames={"#status": "status"},
        ExpressionAttributeValues={
            ":completed": "COMPLETED",
            ":status_code": status_code,
            ":body": json.dumps(body, ensure_ascii=False),
            ":updated_at": int(time.time()),
            ":request_hash": payload_hash,
            ":in_progress": "IN_PROGRESS",
        },
    )


def release(key, payload_hash):
    try:
        _table().delete_item(
            Key={"idempotency_key": key},
            ConditionExpression="request_hash = :request_hash AND #status = :in_progress",
            ExpressionAttributeNames={"#status": "status"},
            ExpressionAttributeValues={
                ":request_hash": payload_hash,
                ":in_progress": "IN_PROGRESS",
            },
        )
    except ClientError as error:
        if error.response.get("Error", {}).get("Code") != "ConditionalCheckFailedException":
            raise
