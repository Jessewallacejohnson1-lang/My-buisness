import { createCommunityApi } from '@hygge/core'
import { supabase } from './supabase'

// Community DB helpers bound to the mobile Supabase client. Shared query logic
// lives in @hygge/core; this is the only place the mobile client is injected.
export const api = createCommunityApi(supabase)
