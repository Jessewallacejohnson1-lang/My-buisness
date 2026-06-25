import { ImageResponse } from 'next/og'

export const size = { width: 1200, height: 630 }
export const contentType = 'image/png'
export const alt = 'Hygge — Everything happening in St. Joseph, in one calm place.'

export default function OpengraphImage() {
  // Simple calendar motif: a rounded card with a header bar and a grid of day dots.
  const dot = (filled: boolean) => (
    <div
      style={{
        width: 26,
        height: 26,
        borderRadius: '50%',
        background: filled ? '#2d4530' : 'rgba(42,42,40,0.14)',
      }}
    />
  )

  return new ImageResponse(
    (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          alignItems: 'center',
          background: '#e1dbc9',
          padding: '0 90px',
          fontFamily: 'Georgia, serif',
        }}
      >
        <div style={{ display: 'flex', flexDirection: 'column', flex: 1 }}>
          <div
            style={{
              fontSize: 20,
              letterSpacing: 10,
              color: '#2a2a28',
              marginBottom: 36,
              textTransform: 'uppercase',
            }}
          >
            HYGGE
          </div>
          <div
            style={{
              display: 'flex',
              flexDirection: 'column',
              fontSize: 76,
              lineHeight: 1.12,
              color: '#2a2a28',
            }}
          >
            <span>Everything happening</span>
            <span style={{ fontStyle: 'italic', color: '#2d4530' }}>
              in St. Joseph.
            </span>
          </div>
          <div
            style={{
              fontSize: 28,
              color: '#61675e',
              marginTop: 34,
              fontFamily: 'sans-serif',
            }}
          >
            Local events, a shared calendar, and a daily quest.
          </div>
        </div>
        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            width: 300,
            height: 300,
            borderRadius: 28,
            background: '#fbfaf5',
            border: '1px solid rgba(0,0,0,0.07)',
            overflow: 'hidden',
          }}
        >
          <div
            style={{
              height: 64,
              background: '#2d4530',
              display: 'flex',
              alignItems: 'center',
              padding: '0 26px',
              color: '#fbfaf5',
              fontSize: 24,
              fontFamily: 'sans-serif',
            }}
          >
            St. Joseph
          </div>
          <div
            style={{
              flex: 1,
              display: 'flex',
              flexWrap: 'wrap',
              alignContent: 'center',
              justifyContent: 'center',
              gap: 22,
              padding: 26,
            }}
          >
            {[false, true, false, false, true, false, false, false, true].map((f, i) => (
              <div key={i} style={{ display: 'flex' }}>
                {dot(f)}
              </div>
            ))}
          </div>
        </div>
      </div>
    ),
    size
  )
}
