import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_ANON_KEY
export const isSupabaseConfigured = Boolean(url && key && !url.includes('your-project'))
export const supabase = isSupabaseConfigured ? createClient(url, key) : null

export async function getRows(table, fallback, query = (q) => q) {
  if (!supabase) return fallback
  const { data, error } = await query(supabase.from(table).select('*'))
  if (error) { console.error(`Could not load ${table}`, error); return fallback }
  return data ?? fallback
}
