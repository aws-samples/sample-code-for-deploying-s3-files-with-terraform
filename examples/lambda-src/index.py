import os
import json

MOUNT_PATH = os.environ.get("MOUNT_PATH", "/mnt/s3data")


def handler(event, context):
    """Process files from S3 Files mount point."""
    files = os.listdir(MOUNT_PATH)

    result = {
        "mount_path": MOUNT_PATH,
        "file_count": len(files),
        "files": files[:20],
    }

    with open(os.path.join(MOUNT_PATH, "lambda-processed.txt"), "w") as f:
        f.write(f"Processed by Lambda at request {context.aws_request_id}\n")

    return {"statusCode": 200, "body": json.dumps(result)}
