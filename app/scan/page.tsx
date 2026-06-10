'use client'
import dynamic from 'next/dynamic'
import Link from 'next/link'

const FoodScanner = dynamic(() => import('../components/FoodScanner'), { ssr: false })

export default function ScanPage() {
  return (
    <div className="min-h-screen bg-stone-50">
      <nav className="flex items-center px-6 py-5 max-w-md mx-auto">
        <Link href="/" className="text-stone-500 hover:text-stone-800 transition-colors text-sm flex items-center gap-2">
          ← Back
        </Link>
        <span className="text-green-800 font-bold text-xl mx-auto pr-12">Grove</span>
      </nav>
      <FoodScanner />
    </div>
  )
}
