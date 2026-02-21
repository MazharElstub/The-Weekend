## Summary

- What changed:
- Why:

## Checklist

- [ ] Branch name follows `feature/*` or `hotfix/*`
- [ ] Commit messages follow conventional format (`feat:`, `fix:`, `chore:`)
- [ ] Tests pass locally
- [ ] Performance smoke checks pass (`testLaunchPerformance`, `testResumePerformance`, `testCoreInteractionPerformanceSmoke`)
- [ ] `CHANGELOG.md` updated if needed
- [ ] Version/build updated for release PRs

## Performance Regression Checklist

- [ ] Launch remains smooth (signed-in path).
- [ ] Foreground resume remains responsive.
- [ ] Add/edit/remove event interactions feel immediate.
- [ ] Settings toggles remain responsive.
- [ ] Calendar import on/off does not introduce input lag.
