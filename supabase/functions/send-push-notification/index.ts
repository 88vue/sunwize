import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { create, getNumericDate } from "https://deno.land/x/djwt@v2.8/mod.ts"

const APNS_KEY_ID = Deno.env.get('APNS_KEY_ID')!
const APNS_TEAM_ID = Deno.env.get('APNS_TEAM_ID')!
const APNS_PRIVATE_KEY = Deno.env.get('APNS_PRIVATE_KEY')! // Base64 encoded .p8 content
const BUNDLE_ID = 'com.sunwize.sunwize'
const APNS_HOST = Deno.env.get('APNS_ENV') === 'production'
  ? 'https://api.push.apple.com'
  : 'https://api.sandbox.push.apple.com'

interface PushNotificationRequest {
  device_tokens: string[]
  title: string
  body: string
  data?: Record<string, any>
  badge?: number
  sound?: string
}

serve(async (req) => {
  try {
    // Verify request is authenticated
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing authorization' }), { status: 401 })
    }

    const payload: PushNotificationRequest = await req.json()
    const { device_tokens, title, body, data, badge, sound = 'default' } = payload

    if (!device_tokens || device_tokens.length === 0) {
      return new Response(JSON.stringify({ error: 'No device tokens provided' }), { status: 400 })
    }

    // Generate JWT for APNs authentication
    // Decode base64 to get PEM content
    const pemContent = atob(APNS_PRIVATE_KEY)

    // Extract the base64 content between BEGIN/END lines
    const pemBase64 = pemContent
      .replace(/-----BEGIN PRIVATE KEY-----/, '')
      .replace(/-----END PRIVATE KEY-----/, '')
      .replace(/\s/g, '')

    // Decode the base64 to get raw DER bytes
    const binaryString = atob(pemBase64)
    const bytes = new Uint8Array(binaryString.length)
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i)
    }

    const key = await crypto.subtle.importKey(
      'pkcs8',
      bytes,
      { name: 'ECDSA', namedCurve: 'P-256' },
      false,
      ['sign']
    )

    const jwt = await create(
      { alg: 'ES256', kid: APNS_KEY_ID },
      {
        iss: APNS_TEAM_ID,
        iat: getNumericDate(new Date()),
      },
      key
    )

    // Send push notification to each device
    const results = await Promise.all(
      device_tokens.map(async (deviceToken) => {
        const notification = {
          aps: {
            alert: {
              title,
              body,
            },
            sound,
            badge,
          },
          ...data,
        }

        const response = await fetch(
          `${APNS_HOST}/3/device/${deviceToken}`,
          {
            method: 'POST',
            headers: {
              'authorization': `bearer ${jwt}`,
              'apns-topic': BUNDLE_ID,
              'apns-priority': '10',
              'apns-push-type': 'alert',
            },
            body: JSON.stringify(notification),
          }
        )

        return {
          deviceToken,
          status: response.status,
          success: response.ok,
          response: response.ok ? null : await response.text(),
        }
      })
    )

    return new Response(JSON.stringify({ results }), {
      headers: { 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})