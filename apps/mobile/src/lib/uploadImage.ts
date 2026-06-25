import { supabase } from './supabase'

/**
 * Uploads a picked image to the Supabase 'event-images' storage bucket and
 * returns its public URL. Returns null on any failure (no bucket yet, network,
 * etc.) so the caller can post the event without an image rather than break.
 * Create the bucket with supabase/migration-event-images.sql.
 */
export async function uploadEventImage(uri: string, contentType = 'image/jpeg'): Promise<string | null> {
  try {
    const resp = await fetch(uri)
    const arrayBuffer = await resp.arrayBuffer()
    const ext = (contentType.split('/')[1] || 'jpg').replace('jpeg', 'jpg')
    const path = `events/${Date.now()}.${ext}`
    const { error } = await supabase.storage.from('event-images').upload(path, arrayBuffer, { contentType })
    if (error) return null
    return supabase.storage.from('event-images').getPublicUrl(path).data.publicUrl
  } catch {
    return null
  }
}
