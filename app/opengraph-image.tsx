import { ImageResponse } from 'next/og'

export const size = { width: 1200, height: 630 }
export const contentType = 'image/png'
export const alt = 'Korina — Eat clean. Train hard. Watch it compound.'

export default function OpengraphImage() {
  const ring = (d: number, color: string, deg: number) => (
    <div
      style={{
        position: 'absolute',
        width: d,
        height: d,
        borderRadius: '50%',
        border: `14px solid ${color}`,
        borderTopColor: 'rgba(0,0,0,0.06)',
        transform: `rotate(${deg}deg)`,
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
          background: '#ffffff',
          padding: '0 90px',
          fontFamily: 'Georgia, serif',
        }}
      >
        <div style={{ display: 'flex', flexDirection: 'column', flex: 1 }}>
          <div
            style={{
              fontSize: 30,
              letterSpacing: 14,
              color: '#1d1f1c',
              marginBottom: 36,
            }}
          >
            K O R I N A
          </div>
          <div
            style={{
              display: 'flex',
              flexDirection: 'column',
              fontSize: 76,
              lineHeight: 1.12,
              color: '#1d1f1c',
            }}
          >
            <span>Eat clean. Train hard.</span>
            <span style={{ fontStyle: 'italic', color: '#1a6fa8' }}>
              Watch it compound.
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
            Every food scored 1–100. Every workout counted.
          </div>
        </div>
        <div
          style={{
            position: 'relative',
            width: 330,
            height: 330,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          {ring(330, '#2e9dba', 40)}
          {ring(244, '#1a6fa8', 110)}
          {ring(158, '#1d1f1c', 200)}
          <div
            style={{
              width: 26,
              height: 26,
              borderRadius: '50%',
              background: '#1d1f1c',
            }}
          />
        </div>
      </div>
    ),
    size
  )
}
