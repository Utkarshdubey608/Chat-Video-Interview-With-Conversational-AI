# Rekognition Proxy (local dev)

The browser cannot call AWS Rekognition directly (it would expose the secret and AWS blocks
cross-origin browser calls). This tiny Express proxy calls Rekognition server-side.

## Run

```powershell
cd rekognition-proxy-local
npm install
$env:AWS_ACCESS_KEY_ID  = "<YOUR_AWS_ACCESS_KEY_ID>"
$env:AWS_SECRET_ACCESS_KEY = "<YOUR_SECRET_ACCESS_KEY>"   # the 40-char secret — REQUIRED
$env:AWS_REGION = "us-east-2"
node server.mjs
```

It listens on `http://localhost:3002/analyze-face`. The platform's `.env.local` already points
`VITE_REKOGNITION_PROXY_URL` here. The IAM user/role for these credentials needs
`rekognition:DetectFaces` (e.g. the `AmazonRekognitionReadOnlyAccess` policy).

## Production

Deploy `../lambda/rekognition-proxy/index.mjs` to AWS Lambda (Node 20.x) with a Function URL +
CORS, attach `AmazonRekognitionReadOnlyAccess` to its execution role, then set
`VITE_REKOGNITION_PROXY_URL` (or the Settings field) to the Function URL. No keys in the browser.
