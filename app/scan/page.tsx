'use client'
import dynamic from 'next/dynamic'
import AppShell from '../components/AppShell'

const FoodScanner = dynamic(() => import('../components/FoodScanner'), { ssr: false })

export default function ScanPage() {
  return (
    <AppShell>
      <FoodScanner />
    </AppShell>
  )
}
