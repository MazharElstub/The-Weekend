# WeekendPlannerIOS

iOS app for planning and organizing weekend activities.

## Repository Rules

- Main branch: `main`
- Feature branches: `feature/<short-description>`
- Hotfix branches: `hotfix/<short-description>`
- Release tags: `vX.Y.Z`

## Versioning

- Marketing version (`CFBundleShortVersionString`): semantic versioning (`MAJOR.MINOR.PATCH`)
- Build number (`CFBundleVersion`): strictly increasing integer

Use the helper script to bump both:

```bash
./scripts/release.sh 1.1.0 5
```

## Release Checklist

1. Merge approved work into `main`.
2. Bump version/build.
3. Update `CHANGELOG.md`.
4. Run performance smoke pass and confirm budgets in `docs/PERFORMANCE_BUDGETS.md`.
5. Verify App Store compliance checklist, including 5.1.1(v) account deletion flow (`Settings` -> `Account` -> `Delete account`).
6. Archive and upload from Xcode.
7. Create and push Git tag (`vX.Y.Z`).

See `CONTRIBUTING.md`, `docs/APP_STORE_COMPLIANCE_CHECKLIST.md`, `docs/PERFORMANCE_BUDGETS.md`, and `docs/PERFORMANCE_BASELINE.md` for full workflow.
