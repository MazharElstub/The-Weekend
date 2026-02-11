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
4. Archive and upload from Xcode.
5. Create and push Git tag (`vX.Y.Z`).

See `CONTRIBUTING.md` for full workflow.
