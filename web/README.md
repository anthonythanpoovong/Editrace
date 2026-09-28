# Web App

Next.js + TypeScript web application for the Viral Template Tool.

## Stack

- **Framework:** Next.js 14+ with TypeScript
- **Database & Auth:** Supabase
- **Storage:** Supabase Storage for video uploads
- **Styling:** TBD (Tailwind recommended)
- **Testing:** TBD (Jest recommended)

## Features

- User registration and login (email via Supabase Auth)
- Video upload flow with job queue integration
- Upload history page with row-level security
- Template breakdown page with scrubbable timeline
- Stripe billing integration (Solo tier + free trial)

## Setup

```bash
npm install
npm run dev
```

## Generated Code

TypeScript types are **generated from `schema/template.schema.json`**. Do not hand-write types — regenerate from schema.
