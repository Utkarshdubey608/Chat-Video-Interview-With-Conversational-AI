// lambda/rekognition-proxy/index.mjs
// Deploy to AWS Lambda (Node.js 20.x). Attach AmazonRekognitionReadOnlyAccess to the
// execution role. Add a Function URL (or API Gateway) with CORS enabled. The resulting
// URL becomes VITE_REKOGNITION_PROXY_URL (or the Settings "AWS Proxy URL" field).
//
// Credentials come from the Lambda execution ROLE — no access keys in code or in the browser.

import { RekognitionClient, DetectFacesCommand } from '@aws-sdk/client-rekognition'

const client = new RekognitionClient({ region: process.env.AWS_REGION ?? 'us-east-2' })

export const handler = async (event) => {
  const headers = {
    'Access-Control-Allow-Origin': '*', // tighten to your domain in production
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST,OPTIONS',
    'Content-Type': 'application/json',
  }

  // CORS preflight (REST API Gateway). Function URLs handle method via requestContext.
  const method = event.httpMethod ?? event.requestContext?.http?.method
  if (method === 'OPTIONS') return { statusCode: 200, headers, body: '' }

  try {
    const { imageBase64, questionIdx, timestampMs } = JSON.parse(event.body ?? '{}')

    if (!imageBase64) {
      return { statusCode: 400, headers, body: JSON.stringify({ success: false, error: 'imageBase64 required' }) }
    }

    const byteEstimate = (imageBase64.length * 3) / 4
    if (byteEstimate < 5000) {
      return { statusCode: 200, headers, body: JSON.stringify({ success: false, reason: 'frame_too_small', questionIdx, timestampMs }) }
    }

    const command = new DetectFacesCommand({
      Image: { Bytes: Buffer.from(imageBase64, 'base64') },
      Attributes: ['ALL'],
    })
    const response = await client.send(command)

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({ success: true, faceDetails: response.FaceDetails ?? [], questionIdx, timestampMs }),
    }
  } catch (error) {
    console.error('Rekognition error:', error)
    return { statusCode: 500, headers, body: JSON.stringify({ success: false, error: error.message }) }
  }
}
