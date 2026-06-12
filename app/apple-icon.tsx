import { ImageResponse } from 'next/og'

export const size = { width: 180, height: 180 }
export const contentType = 'image/png'

/** Home-screen icon — iOS applies its own corner mask, so the artwork is full-bleed. */
export default function AppleIcon() {
  return new ImageResponse(
    (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          background: '#1d1f1c',
        }}
      >
        <div
          style={{
            position: 'absolute',
            width: 118,
            height: 118,
            borderRadius: '50%',
            border: '10px solid #a4be91',
            borderTopColor: 'rgba(255,255,255,0.14)',
            transform: 'rotate(45deg)',
          }}
        />
        <div
          style={{
            position: 'absolute',
            width: 74,
            height: 74,
            borderRadius: '50%',
            border: '10px solid #f4f3ee',
            borderTopColor: 'rgba(255,255,255,0.14)',
            transform: 'rotate(120deg)',
          }}
        />
        <div
          style={{
            width: 22,
            height: 22,
            borderRadius: '50%',
            background: '#a4be91',
          }}
        />
      </div>
    ),
    size
  )
}
