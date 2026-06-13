'use client'

import { useEffect } from 'react'

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  useEffect(() => {
    console.error('Global error boundary:', error)
  }, [error])

  return (
    <html lang="en">
      <body
        style={{
          minHeight: '100vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          background: '#ffffff',
          color: '#1d1f1c',
          fontFamily: 'system-ui, sans-serif',
          textAlign: 'center',
          padding: '0 24px',
        }}
      >
        <div style={{ maxWidth: 360 }}>
          <p
            style={{
              letterSpacing: '0.25em',
              textTransform: 'uppercase',
              color: '#4aa8d4',
              fontSize: 14,
              marginBottom: 24,
            }}
          >
            Korina
          </p>
          <h1 style={{ fontSize: 24, marginBottom: 8 }}>The app crashed</h1>
          <p style={{ fontSize: 14, color: '#61675e', lineHeight: 1.6, marginBottom: 24 }}>
            Something went wrong loading Korina. Reload to get back in.
          </p>
          <button
            onClick={reset}
            style={{
              background: '#1f6e93',
              color: '#fff',
              fontWeight: 600,
              fontSize: 14,
              padding: '12px 24px',
              borderRadius: 12,
              border: 'none',
              cursor: 'pointer',
            }}
          >
            Reload
          </button>
        </div>
      </body>
    </html>
  )
}
