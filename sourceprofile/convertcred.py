import json
import os

HOME_DIR = os.path.expanduser("~")

print(
    f"Converting AWS credentials from JSON to INI format in {HOME_DIR}/.aws/credentials.json")
with open(f"{HOME_DIR}/.aws/credentials.json") as f:
    data = json.load(f)

print(f"Data loaded: {data}")

# Map AWS STS field names to standard AWS credentials file format
field_mapping = {
    'AccessKeyId': 'aws_access_key_id',
    'SecretAccessKey': 'aws_secret_access_key',
    'SessionToken': 'aws_session_token'
}

with open(f"{HOME_DIR}/.aws/credentials", "w") as f:
    f.write('[default]\n')
    for key, value in data.items():
        if key in field_mapping:
            f.write(f'{field_mapping[key]} = {value}\n')
    f.write('\n')
