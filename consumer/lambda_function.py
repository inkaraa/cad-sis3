import json
import os

import boto3
from botocore.exceptions import ClientError

# Client is created outside the handler so connections are reused between warm invocations.
ddb = boto3.client("dynamodb")
TABLE = os.environ["TABLE"]  # DynamoDB table name, e.g. "processed-events"


def lambda_handler(event, context):
    """SQS consumer. Idempotent: the same orderId is processed only once.

    Returns {"batchItemFailures": [...]} so that only the failed messages
    are retried (requires "Report batch item failures" on the SQS trigger).
    """
    failed = []

    for r in event["Records"]:
        try:
            # Test hook for the failure case: this message always fails,
            # is redelivered, and after maxReceiveCount (5) lands in the DLQ.
            if "poison" in r["body"]:
                raise ValueError("poison message")

            m = json.loads(r["body"])

            try:
                # Conditional write = idempotency check.
                # Succeeds only if this orderId has not been recorded yet.
                ddb.put_item(
                    TableName=TABLE,
                    Item={
                        "pk": {"S": m["orderId"]},
                        "total": {"N": str(m.get("total", 0))},
                    },
                    ConditionExpression="attribute_not_exists(pk)",
                )
                print("PROCESSED", m["orderId"])
            except ClientError as e:
                if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
                    # Duplicate delivery: already processed, treat as success.
                    print("DUPLICATE skipped", m["orderId"])
                else:
                    raise

        except Exception as e:
            print("FAILED", r["messageId"], str(e))
            failed.append({"itemIdentifier": r["messageId"]})

    return {"batchItemFailures": failed}
