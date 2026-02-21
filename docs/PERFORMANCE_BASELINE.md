# Performance Baseline

Use this file to track baseline and post-change measurements for the core interaction flows.

## Environment

- Date: 2026-02-15
- Build: Debug (simulator)
- Device: iPhone 16 Pro Simulator (iOS 18.6) and physical iPhone target
- Dataset: Seeded heavy user dataset (multiple calendars, imports enabled, long history)

## Baseline Capture Template

| Flow | Metric | Baseline | Current | Budget | Pass |
| --- | --- | --- | --- | --- | --- |
| Launch (signed in) | ForegroundInteractive | TBD | TBD | <= 400 ms | TBD |
| Foreground resume | ForegroundInteractive | TBD | TBD | <= 400 ms | TBD |
| Add event | TapToUIFeedback p95 | TBD | TBD | <= 100 ms | TBD |
| Add event | LocalMutationCommit p95 | TBD | TBD | <= 150 ms | TBD |
| Edit event | TapToUIFeedback p95 | TBD | TBD | <= 100 ms | TBD |
| Edit event | LocalMutationCommit p95 | TBD | TBD | <= 150 ms | TBD |
| Remove event | TapToUIFeedback p95 | TBD | TBD | <= 100 ms | TBD |
| Toggle protection | TapToUIFeedback p95 | TBD | TBD | <= 100 ms | TBD |
| Settings -> Account | TapToUIFeedback p95 | TBD | TBD | <= 100 ms | TBD |
| Core flows | MainThreadStall | TBD | TBD | no hangs > 250 ms | TBD |
| Steady state memory (sim) | Memory footprint | TBD | TBD | <= 450 MB | TBD |
| Steady state memory (device) | Memory footprint | TBD | TBD | <= 300 MB | TBD |

## Required Artifacts

1. Before/after flame graphs for launch, add event, and foreground resume.
2. Hangs trace showing no >250 ms stalls during core interaction sequence.
3. Allocation/memory snapshots for heavy dataset.
4. Links to xcresult or Instruments exports attached to the release PR.

## Notes

- Keep one entry per release candidate and retain historical rows.
- Any temporary budget waiver must include owner, date, and remediation plan.
