# Website Launch Checklist

Use this checklist before publishing the Weekend Planner website and submitting updated App Store Connect links.

## 1) Environment and config

- [ ] Netlify environment variables are set:
  - `PUBLIC_SUPABASE_URL`
  - `PUBLIC_SUPABASE_ANON_KEY`
  - `PUBLIC_IOS_DEEPLINK`
  - `PUBLIC_APPSTORE_URL`
  - `SUPPORT_CONTACT_EMAIL`
- [ ] `PasswordResetRedirectURL` in iOS app `Info.plist` matches production `/reset-password` URL.
- [ ] Build succeeds locally with `npm run build`.

## 2) Route and content validation

- [ ] `/` renders marketing content and CTA links.
- [ ] `/support` includes visible support alias and troubleshooting guidance.
- [ ] `/privacy` is public and contains current policy date and deletion/contact details.
- [ ] `/terms` is public and legal placeholders are finalized.
- [ ] `/feedback` form submits successfully and lands on `/feedback/success`.
- [ ] `/reset-password` handles valid and invalid reset links.
- [ ] `/reset-password/success` includes app deep link and App Store fallback.
- [ ] 404 page is displayed for unknown URLs.

## 3) Password reset QA

- [ ] Reset email from app opens website `/reset-password`.
- [ ] Valid recovery token allows password update.
- [ ] Expired or invalid links show clear retry instructions.
- [ ] Sensitive URL token fragments are removed from address bar after validation.
- [ ] User can return to app and sign in with updated password.

## 4) Feedback form QA

- [ ] Required fields enforce validation (`category`, `subject`, `message`, `consent`).
- [ ] Optional contact info can be omitted.
- [ ] Honeypot field is present.
- [ ] Submission appears in Netlify Forms dashboard and notification workflow.

## 5) App Store Connect updates

- [ ] Support URL updated to production `/support`.
- [ ] Privacy Policy URL updated to production `/privacy`.
- [ ] App Review notes mention in-app account deletion path.

## 6) Device checks

- [ ] iPhone Safari rendering
- [ ] Desktop Safari rendering
- [ ] Desktop Chrome rendering
- [ ] Keyboard/focus navigation and contrast checks
