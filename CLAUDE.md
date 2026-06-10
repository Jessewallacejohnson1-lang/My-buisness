# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Fitness tracking web app — nutrition logging, workout guidance, and long-term progress tracking. Built with Next.js (App Router), TypeScript, and Tailwind CSS.

## Commands

```bash
npm run dev       # Start development server (localhost:3000)
npm run build     # Production build
npm run lint      # Run ESLint
```

## Architecture

- **`app/`** — App Router pages and layouts. Each folder is a route; `page.tsx` is the UI, `layout.tsx` wraps children.
- **`app/page.tsx`** — Homepage / landing page
- **`public/`** — Static assets (images, icons)
- **`next.config.ts`** — Next.js configuration

## Stack

- **Next.js** (App Router) — routing, SSR, API routes
- **TypeScript** — strict typing throughout
- **Tailwind CSS** — utility-first styling via `@tailwindcss/postcss`

## Notes

- Read `node_modules/next/dist/docs/` before writing Next.js code — this version may differ from training data.
- API routes go in `app/api/[route]/route.ts`
