'use client'

import { useEffect, useRef, useState } from 'react'

interface FoodResult {
  name: string
  brand?: string
  calories: number
  protein: number
  carbs: number
  fat: number
  fiber: number
  servingSize?: string
  image?: string
  barcode: string
}

export default function FoodScanner() {
  const videoRef = useRef<HTMLVideoElement>(null)
  const [scanning, setScanning] = useState(false)
  const [result, setResult] = useState<FoodResult | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const stopRef = useRef<(() => void) | null>(null)

  const startScanner = async () => {
    setScanning(true)
    setResult(null)
    setError(null)

    const { BrowserMultiFormatReader } = await import('@zxing/browser')
    const reader = new BrowserMultiFormatReader()

    const controls = await reader.decodeFromVideoDevice(
      undefined,
      videoRef.current!,
      async (scanResult, err, ctrl) => {
        if (scanResult) {
          ctrl.stop()
          stopRef.current = null
          setScanning(false)
          await lookupFood(scanResult.getText())
        }
      }
    )

    stopRef.current = () => controls.stop()
  }

  const stopScanner = () => {
    if (stopRef.current) {
      stopRef.current()
      stopRef.current = null
    }
    setScanning(false)
  }

  const lookupFood = async (barcode: string) => {
    setLoading(true)
    try {
      const res = await fetch(
        `https://world.openfoodfacts.org/api/v2/product/${barcode}.json`
      )
      const data = await res.json()

      if (data.status === 0 || !data.product) {
        setError('Food not found. Try scanning another barcode.')
        return
      }

      const p = data.product
      const n = p.nutriments || {}

      setResult({
        barcode,
        name: p.product_name || p.abbreviated_product_name || 'Unknown product',
        brand: p.brands?.split(',')[0].trim(),
        calories: Math.round(n['energy-kcal_100g'] ?? n['energy-kcal'] ?? 0),
        protein: Math.round((n.proteins_100g ?? 0) * 10) / 10,
        carbs: Math.round((n.carbohydrates_100g ?? 0) * 10) / 10,
        fat: Math.round((n.fat_100g ?? 0) * 10) / 10,
        fiber: Math.round((n.fiber_100g ?? 0) * 10) / 10,
        servingSize: p.serving_size,
        image: p.image_front_url ?? p.image_url,
      })
    } catch {
      setError('Could not fetch food data. Check your connection.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    return () => {
      if (stopRef.current) stopRef.current()
    }
  }, [])

  return (
    <div className="max-w-md mx-auto px-4 py-10">
      <h1 className="text-2xl font-bold text-stone-900 mb-2">Scan Food</h1>
      <p className="text-stone-500 text-sm mb-8">
        Point your camera at any food barcode to instantly see nutrition info.
      </p>

      {/* Scanner */}
      {!result && (
        <div className="mb-6">
          <div
            className={`relative rounded-3xl overflow-hidden bg-stone-900 aspect-square flex items-center justify-center ${
              scanning ? 'border-2 border-green-500' : 'border-2 border-stone-200'
            }`}
          >
            <video
              ref={videoRef}
              className={`w-full h-full object-cover ${scanning ? 'block' : 'hidden'}`}
              muted
              playsInline
            />
            {!scanning && (
              <div className="text-center px-8">
                <div className="text-6xl mb-4">📷</div>
                <p className="text-stone-400 text-sm">Camera will appear here</p>
              </div>
            )}
            {scanning && (
              <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
                <div className="w-56 h-56 border-2 border-white/60 rounded-2xl relative">
                  <span className="absolute -top-px -left-px w-8 h-8 border-t-4 border-l-4 border-green-400 rounded-tl-xl" />
                  <span className="absolute -top-px -right-px w-8 h-8 border-t-4 border-r-4 border-green-400 rounded-tr-xl" />
                  <span className="absolute -bottom-px -left-px w-8 h-8 border-b-4 border-l-4 border-green-400 rounded-bl-xl" />
                  <span className="absolute -bottom-px -right-px w-8 h-8 border-b-4 border-r-4 border-green-400 rounded-br-xl" />
                </div>
              </div>
            )}
          </div>

          <div className="mt-4 flex gap-3">
            {!scanning ? (
              <button
                onClick={startScanner}
                className="flex-1 bg-green-800 text-white py-3.5 rounded-full font-medium hover:bg-green-900 transition-colors"
              >
                Start scanning
              </button>
            ) : (
              <button
                onClick={stopScanner}
                className="flex-1 border border-stone-300 text-stone-700 py-3.5 rounded-full font-medium hover:bg-stone-100 transition-colors"
              >
                Cancel
              </button>
            )}
          </div>

          {scanning && (
            <p className="text-center text-xs text-stone-400 mt-3">
              Hold steady over a barcode — it'll detect automatically
            </p>
          )}
        </div>
      )}

      {/* Loading */}
      {loading && (
        <div className="text-center py-12">
          <div className="w-10 h-10 border-4 border-green-800 border-t-transparent rounded-full animate-spin mx-auto mb-4" />
          <p className="text-stone-500 text-sm">Looking up food...</p>
        </div>
      )}

      {/* Error */}
      {error && !loading && (
        <div className="bg-red-50 border border-red-200 rounded-2xl p-5 mb-6 text-center">
          <p className="text-red-700 text-sm mb-4">{error}</p>
          <button
            onClick={startScanner}
            className="bg-green-800 text-white px-6 py-2.5 rounded-full text-sm font-medium hover:bg-green-900 transition-colors"
          >
            Try again
          </button>
        </div>
      )}

      {/* Result */}
      {result && !loading && (
        <div className="space-y-4">
          <div className="bg-white rounded-3xl border border-stone-100 shadow-sm overflow-hidden">
            {result.image && (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={result.image}
                alt={result.name}
                className="w-full h-48 object-contain bg-stone-50 p-4"
              />
            )}
            <div className="p-6">
              <div className="mb-4">
                {result.brand && (
                  <p className="text-xs text-stone-400 uppercase tracking-widest mb-1">{result.brand}</p>
                )}
                <h2 className="text-xl font-bold text-stone-900">{result.name}</h2>
                {result.servingSize && (
                  <p className="text-sm text-stone-400 mt-1">Serving size: {result.servingSize}</p>
                )}
              </div>

              {/* Calories */}
              <div className="bg-green-800 rounded-2xl p-4 text-white text-center mb-4">
                <p className="text-4xl font-bold">{result.calories}</p>
                <p className="text-green-200 text-sm mt-1">kcal per 100g</p>
              </div>

              {/* Macros */}
              <div className="grid grid-cols-4 gap-2">
                {[
                  { label: 'Protein', value: result.protein, unit: 'g', color: 'bg-amber-100 text-amber-800' },
                  { label: 'Carbs', value: result.carbs, unit: 'g', color: 'bg-orange-100 text-orange-800' },
                  { label: 'Fat', value: result.fat, unit: 'g', color: 'bg-green-100 text-green-800' },
                  { label: 'Fiber', value: result.fiber, unit: 'g', color: 'bg-stone-100 text-stone-700' },
                ].map((m) => (
                  <div key={m.label} className={`${m.color} rounded-xl p-3 text-center`}>
                    <p className="text-lg font-bold">{m.value}{m.unit}</p>
                    <p className="text-xs mt-0.5 opacity-70">{m.label}</p>
                  </div>
                ))}
              </div>
            </div>
          </div>

          <button
            className="w-full bg-green-800 text-white py-3.5 rounded-full font-medium hover:bg-green-900 transition-colors"
          >
            Add to today&apos;s log
          </button>

          <button
            onClick={() => { setResult(null); setError(null) }}
            className="w-full border border-stone-300 text-stone-700 py-3.5 rounded-full font-medium hover:bg-stone-100 transition-colors"
          >
            Scan another
          </button>
        </div>
      )}
    </div>
  )
}
