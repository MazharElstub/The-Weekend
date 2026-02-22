# Weekend Planner Website

Companion website for App Store support/privacy links, password reset landing, and user feedback intake.

## Routes

- `/` Home / marketing
- `/support` App support and contact info
- `/privacy` Privacy policy
- `/terms` Terms of use
- `/feedback` Support/bug/feature form (Netlify Forms)
- `/feedback/success` Form confirmation
- `/reset-password` Password reset flow
- `/reset-password/success` Password reset confirmation

## Setup

1. Copy `.env.example` to `.env` and fill values.
2. Install dependencies:

```bash
npm install
```

3. Run locally:

```bash
npm run dev
```

4. Build for production:

```bash
npm run build
```

## Netlify

Deployment is configured from repo root via `netlify.toml`:

- Base directory: `website`
- Publish directory: `dist`
- Build command: `npm run build`

Configure environment variables in Netlify Site Settings before production deploy.
