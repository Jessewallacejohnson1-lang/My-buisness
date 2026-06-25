import type { MetadataRoute } from 'next'

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'Hygge — St. Joseph',
    short_name: 'Hygge',
    description:
      'Everything happening in St. Joseph, in one calm place. Local events, a shared calendar, and a daily quest.',
    start_url: '/community',
    display: 'standalone',
    orientation: 'portrait',
    background_color: '#fbfaf5',
    theme_color: '#e1dbc9',
    icons: [
      { src: '/icon.svg', sizes: 'any', type: 'image/svg+xml', purpose: 'any' },
      { src: '/apple-icon', sizes: '180x180', type: 'image/png' },
    ],
  }
}
