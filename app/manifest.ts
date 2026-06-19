import type { MetadataRoute } from 'next'

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'Hygge Health',
    short_name: 'Hygge',
    description:
      'Every food scored 1–100. Every workout counted. Daily habits turned into rings you can watch grow.',
    start_url: '/dashboard',
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
