# start.ps1 — launches the local Rekognition proxy with AWS credentials.
# ⚠ LOCAL DEV ONLY. Fill in your own AWS credentials below; do not commit real keys.
# Usage:  cd rekognition-proxy-local ;  .\start.ps1
$env:AWS_ACCESS_KEY_ID     = '<YOUR_AWS_ACCESS_KEY_ID>'
$env:AWS_SECRET_ACCESS_KEY = '<YOUR_AWS_SECRET_ACCESS_KEY>'
$env:AWS_REGION            = 'us-east-2'
node server.mjs
