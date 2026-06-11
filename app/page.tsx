import Link from 'next/link'

export default function Home() {
  return (
    <div className="min-h-screen bg-stone-50 text-stone-900" style={{ fontFamily: 'var(--font-nunito), sans-serif' }}>

      {/* Navbar */}
      <nav className="flex items-center justify-between px-6 py-5 max-w-6xl mx-auto">
        <span className="text-xl font-bold text-green-800 tracking-[0.2em] uppercase" style={{ fontFamily: 'var(--font-nunito), sans-serif' }}>Grove</span>
        <div className="flex items-center gap-6">
          <Link href="/dashboard" className="text-stone-500 hover:text-stone-800 text-sm transition-colors">Dashboard</Link>
          <Link href="/meal-log" className="text-stone-500 hover:text-stone-800 text-sm transition-colors">Meal log</Link>
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
          <h1 className="text-5xl leading-tight text-stone-900 mb-6" style={{ fontFamily: 'var(--font-dm-serif), serif', fontWeight: 400 }}>
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
          <h2 className="text-4xl text-center text-stone-900 mb-4" style={{ fontFamily: 'var(--font-dm-serif), serif', fontWeight: 400 }}>Everything you need</h2>
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
        <h2 className="text-4xl text-center text-stone-900 mb-4" style={{ fontFamily: 'var(--font-dm-serif), serif', fontWeight: 400 }}>Simple by design</h2>
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

      {/* Barcode scanner spotlight */}
      <section className="py-24 bg-stone-900 overflow-hidden">
        <div className="max-w-6xl mx-auto px-6 grid grid-cols-1 lg:grid-cols-2 gap-16 items-center">
          {/* Scanner mock */}
          <div className="relative">
            <div className="bg-stone-800 rounded-3xl p-6 border border-stone-700 shadow-2xl">
              <div className="flex items-center justify-between mb-5">
                <span className="text-stone-400 text-xs tracking-widest uppercase">Scan food</span>
                <span className="w-2 h-2 rounded-full bg-green-400 animate-pulse" />
              </div>
              {/* Viewfinder */}
              <div className="relative bg-stone-900 rounded-2xl aspect-video flex items-center justify-center overflow-hidden">
                <div className="absolute inset-0 opacity-20" style={{
                  backgroundImage: 'repeating-linear-gradient(0deg, transparent, transparent 30px, #6b7280 30px, #6b7280 31px), repeating-linear-gradient(90deg, transparent, transparent 30px, #6b7280 30px, #6b7280 31px)'
                }} />
                <div className="absolute inset-6 border-2 border-green-400 rounded-xl" style={{ boxShadow: '0 0 30px rgba(74,222,128,0.2)' }}>
                  <span className="absolute -top-px left-4 right-4 h-px bg-green-400 opacity-80" style={{ animation: 'none' }} />
                  <div className="absolute top-0 left-0 w-4 h-4 border-t-2 border-l-2 border-green-400 rounded-tl" />
                  <div className="absolute top-0 right-0 w-4 h-4 border-t-2 border-r-2 border-green-400 rounded-tr" />
                  <div className="absolute bottom-0 left-0 w-4 h-4 border-b-2 border-l-2 border-green-400 rounded-bl" />
                  <div className="absolute bottom-0 right-0 w-4 h-4 border-b-2 border-r-2 border-green-400 rounded-br" />
                </div>
                <span className="text-stone-500 text-sm">Point at a barcode</span>
              </div>
              {/* Result card */}
              <div className="mt-4 bg-stone-700/60 rounded-2xl p-4 flex items-center gap-4 border border-stone-600">
                <div className="w-12 h-12 rounded-xl bg-amber-500/20 flex items-center justify-center text-2xl shrink-0">🥜</div>
                <div className="flex-1 min-w-0">
                  <p className="text-white font-semibold text-sm truncate">Kind Dark Chocolate Nuts</p>
                  <p className="text-stone-400 text-xs mt-0.5">1 bar · 200 cal · 6g protein</p>
                </div>
                <button className="bg-green-600 text-white text-xs font-medium px-3 py-1.5 rounded-full shrink-0 hover:bg-green-500 transition-colors">
                  Add
                </button>
              </div>
            </div>
            {/* Glow */}
            <div className="absolute -inset-4 bg-green-800/20 rounded-3xl blur-3xl -z-10" />
          </div>
          {/* Copy */}
          <div>
            <span className="inline-block text-green-400 text-xs font-semibold tracking-widest uppercase mb-5">Instant logging</span>
            <h2 className="text-4xl text-white mb-6 leading-snug" style={{ fontFamily: 'var(--font-dm-serif), serif', fontWeight: 400 }}>
              Scan it.<br />Logged in a second.
            </h2>
            <p className="text-stone-400 leading-relaxed mb-8 text-lg">
              Point your camera at any barcode and get the full nutrition breakdown instantly — calories, protein, carbs, fats. No typing, no searching.
            </p>
            <ul className="space-y-3 mb-10">
              {[
                'Works on 700,000+ packaged foods',
                'Instantly adds to your daily log',
                'Remembers your frequent foods',
              ].map((item) => (
                <li key={item} className="flex items-center gap-3 text-stone-300 text-sm">
                  <span className="w-5 h-5 rounded-full bg-green-800 border border-green-600 flex items-center justify-center shrink-0">
                    <svg viewBox="0 0 10 10" className="w-3 h-3 text-green-400" fill="none">
                      <path d="M2 5l2 2 4-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                  </span>
                  {item}
                </li>
              ))}
            </ul>
            <Link href="/scan" className="inline-flex items-center gap-2 bg-green-600 hover:bg-green-500 text-white px-7 py-3.5 rounded-full font-medium transition-colors">
              Try the scanner
            </Link>
          </div>
        </div>
      </section>

      {/* Testimonials */}
      <section className="py-24 bg-amber-50">
        <div className="max-w-6xl mx-auto px-6">
          <div className="text-center mb-14">
            <span className="text-amber-700 text-xs font-semibold tracking-widest uppercase block mb-3">Real people, real results</span>
            <h2 className="text-4xl text-stone-900" style={{ fontFamily: 'var(--font-dm-serif), serif', fontWeight: 400 }}>
              The habit sticks this time
            </h2>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            {[
              {
                quote: "I've tried every fitness app. Grove is the only one I've kept open for more than a week. The scanner alone saves me ten minutes a day.",
                name: 'Maya R.',
                detail: 'Lost 14 lbs in 3 months',
                avatar: '🧘‍♀️',
              },
              {
                quote: "Seeing the calendar fill up with green streaks is more motivating than any notification or reward badge I've ever earned.",
                name: 'Jordan T.',
                detail: '62-day streak',
                avatar: '🏃‍♂️',
              },
              {
                quote: "I finally understand what I'm actually eating. The macro breakdown changed how I cook, not just how I log.",
                name: 'Priya S.',
                detail: 'Hit protein goal 47 days straight',
                avatar: '🥗',
              },
            ].map((t) => (
              <div key={t.name} className="bg-white rounded-2xl p-7 border border-stone-100 shadow-sm flex flex-col">
                <p className="text-stone-600 leading-relaxed flex-1 mb-6">&ldquo;{t.quote}&rdquo;</p>
                <div className="flex items-center gap-3 pt-5 border-t border-stone-100">
                  <span className="text-2xl">{t.avatar}</span>
                  <div>
                    <p className="font-semibold text-stone-900 text-sm">{t.name}</p>
                    <p className="text-stone-400 text-xs">{t.detail}</p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="bg-green-800 py-24 text-white text-center">
        <div className="max-w-2xl mx-auto px-6">
          <h2 className="text-5xl mb-4" style={{ fontFamily: 'var(--font-dm-serif), serif', fontWeight: 400 }}>Ready to start?</h2>
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
        <p className="text-white font-bold text-xl mb-2 tracking-[0.2em] uppercase">Grove</p>
        <p>© 2026 Grove. Built with care.</p>
      </footer>
    </div>
  );
}
