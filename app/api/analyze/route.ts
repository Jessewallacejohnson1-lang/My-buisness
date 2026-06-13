import { NextResponse } from 'next/server'
import Anthropic from '@anthropic-ai/sdk'
import { zodOutputFormat } from '@anthropic-ai/sdk/helpers/zod'
import { z } from 'zod'
import { createClient } from '@/lib/supabase/server'
import { DIET_LABELS, type Diet } from '@/lib/profile'

const FoodItem = z.object({
  name: z.string().describe('Short food name, e.g. "Grilled chicken breast"'),
  portion: z.string().describe('Human-readable portion estimate, e.g. "1 cup, ~150g"'),
  calories: z.number().describe('Estimated kcal for this portion'),
  protein: z.number().describe('Grams of protein for this portion'),
  carbs: z.number().describe('Grams of carbohydrates for this portion'),
  fat: z.number().describe('Grams of fat for this portion'),
  fibre: z.number().describe('Grams of fibre for this portion'),
  score: z
    .number()
    .describe('Clean score 1-100: whole unprocessed foods score high, ultra-processed foods score low'),
  badges: z
    .array(z.string())
    .describe('Positive attributes, e.g. "Whole Food", "High Protein", "High Fibre"'),
  flags: z
    .array(z.string())
    .describe('Concerns, e.g. "Likely contains added sugar", "Fried — high in refined oils"'),
})

const Analysis = z.object({
  foods: z.array(FoodItem).describe('Each distinct food visible in the photo'),
  confidence: z.enum(['high', 'medium', 'low']),
  note: z
    .string()
    .describe('One short sentence of context for the user, e.g. what was hard to judge'),
})

export type PhotoAnalysis = z.infer<typeof Analysis>

const SYSTEM = `You are the nutrition analyst inside Korina, a clean-eating fitness tracker.
Given a photo of food, identify each distinct food item and estimate its nutrition for the
portion actually visible (not per 100g). Use the same clean-score philosophy as the rest of
the app: whole, unprocessed foods (fresh produce, plain meats, whole grains) score 80-100;
lightly processed foods score 55-79; processed foods with additives or refined ingredients
score 30-54; ultra-processed foods, sweets, and fried fast food score 1-29.
Be realistic with portion sizes — use plate size, cutlery, and packaging for scale.
If the photo contains no food, return an empty foods array and explain in the note.`

export async function POST(req: Request) {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) {
    return NextResponse.json({ error: 'Sign in to analyze photos.' }, { status: 401 })
  }

  if (!process.env.ANTHROPIC_API_KEY) {
    return NextResponse.json(
      { error: 'Photo analysis isn’t set up yet — add an ANTHROPIC_API_KEY to the environment.' },
      { status: 503 }
    )
  }

  let image: string, media_type: 'image/jpeg' | 'image/png' | 'image/webp'
  try {
    const body = await req.json()
    image = body.image
    media_type = body.media_type ?? 'image/jpeg'
    if (typeof image !== 'string' || image.length === 0) throw new Error('missing image')
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(media_type)) throw new Error('bad type')
    // base64 encodes ~4/3 of the original bytes; 6MB base64 ≈ 4.5MB image
    if (image.length > 6_000_000) throw new Error('too large')
  } catch (e) {
    const msg = e instanceof Error ? e.message : ''
    if (msg === 'too large')
      return NextResponse.json({ error: 'Image too large. Max 4.5 MB.' }, { status: 413 })
    return NextResponse.json({ error: 'Send { image: base64, media_type }.' }, { status: 400 })
  }

  // Personalize: flag foods that conflict with the user's diet.
  const { data: prof } = await supabase.from('profiles').select('diet').maybeSingle()
  const diet = prof?.diet as Diet | undefined
  const dietNote =
    diet && diet !== 'none'
      ? `\nThis user follows a ${DIET_LABELS[diet]} diet. If any food in the photo conflicts with it, add a flag stating the conflict (e.g. "Contains meat — not vegetarian").`
      : ''

  const client = new Anthropic()

  try {
    const response = await client.messages.parse({
      model: 'claude-opus-4-8',
      max_tokens: 16000,
      thinking: { type: 'adaptive' },
      system: SYSTEM + dietNote,
      messages: [
        {
          role: 'user',
          content: [
            { type: 'image', source: { type: 'base64', media_type, data: image } },
            {
              type: 'text',
              text: 'Identify every food in this photo and estimate nutrition for the visible portions.',
            },
          ],
        },
      ],
      output_config: { format: zodOutputFormat(Analysis) },
    })

    if (!response.parsed_output) {
      return NextResponse.json({ error: 'Couldn’t read the photo. Try a clearer shot.' }, { status: 422 })
    }
    return NextResponse.json(response.parsed_output)
  } catch (err) {
    if (err instanceof Anthropic.APIError) {
      console.error('analyze: Anthropic API error', err.status, err.message)
      return NextResponse.json(
        { error: 'The analyzer is having trouble right now. Try again in a moment.' },
        { status: 502 }
      )
    }
    throw err
  }
}
