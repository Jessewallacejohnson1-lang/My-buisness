import Link from 'next/link'

export default function Home() {
  return (
    <div className="min-h-screen bg-stone-50 text-stone-900 font-sans">

      {/* Navbar */}
      <nav className="flex items-center justify-between px-6 py-5 max-w-6xl mx-auto">
        <span className="text-2xl font-bold text-green-800">Grove</span>
        <div className="flex items-center gap-6">
          <a href="#features" className="text-stone-500 hover:text-stone-800 text-sm transition-colors">Features</a>
          <a href="#how-it-works" className="text-stone-500 hover:text-stone-800 text-sm transition-colors">How it works</a>
          <Link href="/scan" className="border border-green-800 text-green-800 px-5 py-2.5 rounded-full text-sm font-medium hover:bg-green-50 transition-colors">
            📷 Scan food
          </Link>
          <button className="bg-green-800 text-white px-5 py-2.5 rounded-full text-sm font-medium hover:bg-green-900 transition-colors">
            Get started free
          </button>
        </div>
      </nav>

      {/* Hero */}
      <section className="max-w-6xl mx-auto px-6 pt-16 pb-24 grid grid-cols-1 lg:grid-cols-2 gap-16 items-center">
        <div>
          <span className="inline-block bg-amber-100 text-amber-800 text-xs font-semibold px-3 py-1 rounded-full mb-6 tracking-widest uppercase">
            Your wellness companion
          </span>
          <h1 className="text-5xl font-bold leading-tight text-stone-900 mb-6">
            Feel good,<br />inside and out.
          </h1>
          <p className="text-lg text-stone-500 mb-10 leading-relaxed max-w-md">
            Track your nutrition, follow guided workouts, and watch your progress
            unfold — all in one place, built for the long game.
          </p>
          <div className="flex gap-4 flex-wrap">
            <button className="bg-green-800 text-white px-7 py-3.5 rounded-full font-medium hover:bg-green-900 transition-colors">
              Start for free
            </button>
            <button className="border border-stone-300 text-stone-700 px-7 py-3.5 rounded-full font-medium hover:bg-stone-100 transition-colors">
              See how it works
            </button>
          </div>
        </div>

        {/* App preview card */}
        <div className="bg-white rounded-3xl shadow-xl p-6 space-y-4 border border-stone-100">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-xs text-stone-400 uppercase tracking-widest">Today&apos;s progress</p>
              <p className="text-xl font-bold text-stone-900 mt-0.5">Monday, Jun 9</p>
            </div>
            <div className="w-10 h-10 rounded-full bg-green-100 flex items-center justify-center text-lg">🌱</div>
          </div>

          <div className="bg-stone-50 rounded-2xl p-4 flex items-center gap-4">
            <div className="relative w-16 h-16 shrink-0">
              <svg viewBox="0 0 36 36" className="w-16 h-16 -rotate-90">
                <circle cx="18" cy="18" r="15.9" fill="none" stroke="#e7e5e4" strokeWidth="3" />
                <circle cx="18" cy="18" r="15.9" fill="none" stroke="#166534" strokeWidth="3"
                  strokeDasharray="68 32" strokeLinecap="round" />
              </svg>
              <span className="absolute inset-0 flex items-center justify-center text-xs font-bold text-stone-800">68%</span>
            </div>
            <div>
              <p className="font-semibold text-stone-800">1,420 / 2,100 cal</p>
              <p className="text-xs text-stone-400 mt-0.5">680 calories remaining</p>
            </div>
          </div>

          <div className="grid grid-cols-3 gap-3">
            {[
              { label: 'Protein', value: '82g', pct: '74%', color: 'bg-amber-400' },
              { label: 'Carbs', value: '156g', pct: '60%', color: 'bg-orange-400' },
              { label: 'Fat', value: '44g', pct: '55%', color: 'bg-green-500' },
            ].map((m) => (
              <div key={m.label} className="bg-stone-50 rounded-xl p-3">
                <p className="text-xs text-stone-400 mb-1">{m.label}</p>
                <p className="font-semibold text-sm text-stone-800">{m.value}</p>
                <div className="mt-2 h-1.5 bg-stone-200 rounded-full overflow-hidden">
                  <div className={`h-full rounded-full ${m.color}`} style={{ width: m.pct }} />
                </div>
              </div>
            ))}
          </div>

          <div className="bg-green-800 rounded-2xl p-4 text-white flex items-center justify-between">
            <div>
              <p className="text-xs text-green-300 mb-1">Today&apos;s workout</p>
              <p className="font-semibold">Upper Body Strength</p>
              <p className="text-xs text-green-300 mt-0.5">6 exercises · 45 min</p>
            </div>
            <div className="w-10 h-10 rounded-full bg-white/20 flex items-center justify-center text-white font-bold">
              ▶
            </div>
          </div>
        </div>
      </section>

      {/* Features */}
      <section id="features" className="bg-amber-50 py-24">
        <div className="max-w-6xl mx-auto px-6">
          <h2 className="text-3xl font-bold text-center text-stone-900 mb-4">Everything you need</h2>
          <p className="text-center text-stone-500 mb-14 max-w-xl mx-auto">
            No fluff. Just the tools that actually help you build sustainable habits.
          </p>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
            {[
              {
                icon: '🥦',
                title: 'Daily Nutrition',
                desc: 'Log meals and track calories, protein, carbs, fats, vitamins, and minerals — with a database of thousands of foods.',
              },
              {
                icon: '🏋️',
                title: 'Workout Guidance',
                desc: 'Follow curated workout plans or build your own. Log sets, reps, and weight. Every session tracked.',
              },
              {
                icon: '📅',
                title: 'Progress Calendar',
                desc: 'See months of data at a glance. Streaks, milestones, weight trends — your journey, visualized.',
              },
            ].map((f) => (
              <div key={f.title} className="bg-white rounded-2xl p-8 shadow-sm border border-stone-100">
                <div className="text-4xl mb-5">{f.icon}</div>
                <h3 className="text-xl font-semibold text-stone-900 mb-3">{f.title}</h3>
                <p className="text-stone-500 leading-relaxed">{f.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* How it works */}
      <section id="how-it-works" className="py-24 max-w-6xl mx-auto px-6">
        <h2 className="text-3xl font-bold text-center text-stone-900 mb-4">Simple by design</h2>
        <p className="text-center text-stone-500 mb-16 max-w-xl mx-auto">
          Getting started takes two minutes. Building the habit takes consistency — we make that easy.
        </p>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-10">
          {[
            {
              step: '01',
              title: 'Set your goals',
              desc: 'Tell us where you want to go — lose weight, build muscle, eat better, or all three.',
            },
            {
              step: '02',
              title: 'Log your day',
              desc: "Quickly log meals and workouts. We'll do the math and keep you on track.",
            },
            {
              step: '03',
              title: 'Watch yourself grow',
              desc: 'Your calendar fills up. Your habits compound. The results follow.',
            },
          ].map((s) => (
            <div key={s.step} className="flex gap-5">
              <span className="text-5xl font-bold text-stone-200 shrink-0 leading-none">{s.step}</span>
              <div className="pt-1">
                <h3 className="text-xl font-semibold text-stone-900 mb-2">{s.title}</h3>
                <p className="text-stone-500 leading-relaxed">{s.desc}</p>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* CTA */}
      <section className="bg-green-800 py-24 text-white text-center">
        <div className="max-w-2xl mx-auto px-6">
          <h2 className="text-4xl font-bold mb-4">Ready to start?</h2>
          <p className="text-green-200 text-lg mb-10">
            Join the waitlist and be the first to know when we launch.
          </p>
          <div className="flex gap-3 max-w-sm mx-auto">
            <input
              type="email"
              placeholder="your@email.com"
              className="flex-1 px-5 py-3 rounded-full text-stone-900 focus:outline-none min-w-0"
            />
            <button className="bg-amber-500 hover:bg-amber-600 text-white px-6 py-3 rounded-full font-medium whitespace-nowrap transition-colors">
              Join waitlist
            </button>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="bg-stone-900 text-stone-400 py-10 text-center text-sm">
        <p className="text-white font-semibold text-xl mb-2">Grove</p>
        <p>© 2026 Grove. Built with care.</p>
      </footer>
    </div>
  );
}
