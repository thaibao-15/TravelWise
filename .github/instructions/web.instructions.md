---
name: TravelWise Web Rules
description: "Use when changing the Next.js web app, React components, TypeScript services, hooks, pages, styling, SSE streaming, chat UI, voice UI, or frontend tests."
applyTo: "apps/web/**/*.{ts,tsx,css}"
---

# TravelWise Web Rules

## Next.js and React

- Follow the App Router structure already used in `apps/web`.
- Add `"use client"` only to components that use state, hooks, event handlers or browser APIs.
- Reuse existing services, hooks, types and UI components before adding alternatives.
- Keep TypeScript types explicit and preserve API response contracts from `apps/api`.
- Use dynamic route folders such as `[id]` consistently with the existing app.

## Async, chat and voice

- For SSE streaming, audio callbacks and asynchronous event handlers, use `useRef` and `useCallback` where needed to avoid stale closures.
- Review `useEffect` dependencies and cleanup to prevent races, duplicate subscriptions and updates after unmount.
- Stop microphone recording before playing assistant audio to prevent speaker feedback loops.
- Use `StreamingTTSQueue` for streaming text-to-speech so the first sentence can play without waiting for the entire response.
- Keep voice responses natural and free of Markdown, emoji and repeated greetings.

## UI and styling

- Use Tailwind CSS and the existing dark theme conventions: `bg-slate-950`, `text-slate-100` and `border-slate-800`.
- Preserve responsive layouts and existing accessibility behavior.
- Prefer small, consistent transitions and micro-interactions over unrelated visual redesigns.

## Validation

From `apps\web` run:

```powershell
bun run lint
bun run build
```

Keep `bun.lock` synchronized when changing dependencies. Do not expose secrets in client code or browser storage.
