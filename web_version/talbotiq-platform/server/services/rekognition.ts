import { RekognitionClient, DetectFacesCommand } from '@aws-sdk/client-rekognition'

const env = (k: string) => (process.env[k] ?? '').trim()

export function rekognitionConfigured(): boolean {
  return !!(env('AWS_ACCESS_KEY_ID') && env('AWS_SECRET_ACCESS_KEY'))
}

let client: RekognitionClient | null = null
function rek(): RekognitionClient | null {
  if (!rekognitionConfigured()) return null
  if (!client) {
    client = new RekognitionClient({
      region: env('AWS_REGION') || 'us-east-2',
      credentials: { accessKeyId: env('AWS_ACCESS_KEY_ID'), secretAccessKey: env('AWS_SECRET_ACCESS_KEY') },
    })
  }
  return client
}

/** DetectFaces on a base64 JPEG frame. Mirrors the avatar proxy's response shape. */
export async function detectFaces(imageBase64: string): Promise<
  | { success: true; faceDetails: unknown[] }
  | { success: false; error: string }
> {
  const c = rek()
  if (!c) return { success: false, error: 'Rekognition is not configured on the server' }
  const out = await c.send(new DetectFacesCommand({ Image: { Bytes: Buffer.from(imageBase64, 'base64') }, Attributes: ['ALL'] }))
  return { success: true, faceDetails: out.FaceDetails ?? [] }
}
