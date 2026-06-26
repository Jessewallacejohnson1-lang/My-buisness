import Anthropic from '@anthropic-ai/sdk'
import { NextResponse } from 'next/server'

// Server-only: keeps ANTHROPIC_API_KEY off the client.
export const runtime = 'nodejs'

type Body = {
  kind: string
  title: string
  location?: string | null
  description?: string | null
  cadence?: string | null
  length?: string | null
  difficulty?: string | null
  image_url?: string | null
}

const SYSTEM = `You moderate posts for Hygge, a warm, calm, hyper-local community app for the real town of St. Joseph, Minnesota. Neighbors post events, clubs, trails, and notices.

Approve a post when it is a plausible local community post of its stated kind, is not spam/advertising/scam, is not abusive/hateful/harassing, and is not sexual, violent, or otherwise inappropriate. If an image is provided, it must also be appropriate (nothing sexual, graphic, hateful, or unsafe). Tone should read like a neighbor, but minor wording is fine — do not reject for being unpolished.

Reject only with a clear, kind, specific reason the poster can act on.

Respond with ONLY a JSON object: {"ok": true|false, "reason": "<short reason, empty string when ok>"}`

export async function POST(req: Request) {
  const key = process.env.ANTHROPIC_API_KEY
  if (!key) {
    return NextResponse.json({ ok: false, reason: 'Moderation unavailable.' }, { status: 503 })
  }

  let body: Body
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ ok: false, reason: 'Bad request.' }, { status: 400 })
  }

  const anthropic = new Anthropic({ apiKey: key })

  const facts = [
    `Kind: ${body.kind}`,
    `Title: ${body.title}`,
    body.location ? `Location: ${body.location}` : null,
    body.cadence ? `When: ${body.cadence}` : null,
    body.length ? `Length: ${body.length}` : null,
    body.difficulty ? `Difficulty: ${body.difficulty}` : null,
    body.description ? `Description: ${body.description}` : null,
  ].filter(Boolean).join('\n')

  // Build content: text always; image block only when a photo URL is present.
  const content: Anthropic.ContentBlockParam[] = [{ type: 'text', text: facts }]
  if (body.image_url) {
    content.push({ type: 'image', source: { type: 'url', url: body.image_url } })
  }

  try {
    const msg = await anthropic.messages.create({
      // Use the model id confirmed via the claude-api skill (fast judge tier).
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 200,
      system: SYSTEM,
      messages: [{ role: 'user', content }],
    })
    const text = msg.content
      .filter((b): b is Anthropic.TextBlock => b.type === 'text')
      .map((b) => b.text)
      .join('')
      .trim()
    const match = text.match(/\{[\s\S]*\}/)
    if (!match) throw new Error('No JSON in model output')
    const parsed = JSON.parse(match[0]) as { ok?: boolean; reason?: string }
    return NextResponse.json({ ok: !!parsed.ok, reason: parsed.reason ?? '' })
  } catch {
    // Fail-closed: caller saves the post as pending for manual review.
    return NextResponse.json({ ok: false, reason: 'Could not auto-check.' }, { status: 502 })
  }
}
