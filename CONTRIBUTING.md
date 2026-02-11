# Contributing Guide

## Branching Model

- `main` is always releasable.
- Use short-lived feature branches named `feature/<short-description>`.
- Use short-lived hotfix branches named `hotfix/<short-description>`.
- Merge to `main` through pull requests.

## Commit Message Format

Use conventional commit prefixes:

- `feat:` for user-facing features
- `fix:` for bug fixes
- `chore:` for tooling/docs/maintenance

Examples:

- `feat: add weekend weather summary on trip cards`
- `fix: prevent duplicate itinerary items`
- `chore: update release checklist`

## Versioning Rules

- `MARKETING_VERSION` maps to `CFBundleShortVersionString` and follows `MAJOR.MINOR.PATCH`.
- `CURRENT_PROJECT_VERSION` maps to `CFBundleVersion` and must strictly increase for every TestFlight/App Store upload.
- Every App Store release must have a Git tag in `vX.Y.Z` format on `main`.

## Release Workflow

1. Merge completed work into `main`.
2. Bump marketing version and build number.
3. Update `CHANGELOG.md`.
4. Archive and upload in Xcode.
5. Create tag `vX.Y.Z` on the release commit.
6. Push branch and tag.

## Hotfix Workflow

1. Branch from `main` using `hotfix/<short-description>`.
2. Apply and test the fix.
3. Merge back to `main`.
4. Increment patch version and build number.
5. Tag and ship.
