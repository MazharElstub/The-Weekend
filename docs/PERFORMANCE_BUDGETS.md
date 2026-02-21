# Performance Budgets

This document defines the minimum performance gates that must pass before shipping an App Store build.

## Core Budgets

| Metric | Target |
| --- | --- |
| `TapToUIFeedback` p95 | <= 100 ms |
| `LocalMutationCommit` p95 | <= 150 ms |
| `ForegroundInteractive` | <= 400 ms to usable UI |
| `MainThreadStall` | No hangs > 250 ms in core flows |
| `Memory` steady-state (simulator) | <= 450 MB |
| `Memory` steady-state (physical device) | <= 300 MB |

## Required Flows

Run perf checks for:

1. Signed-in app launch.
2. Foreground resume from background.
3. Add event.
4. Edit event.
5. Remove event.
6. Toggle protection.
7. Open `Settings` -> `Account`.

## Profiling Procedure

1. Build Debug for simulator and run with representative seeded data.
2. Capture Instruments traces:
   - Time Profiler
   - Hangs
   - Allocations
   - Main Thread Checker
3. Record p95 and max for the metrics above.
4. Compare against the latest baseline in `docs/PERFORMANCE_BASELINE.md`.
5. If any budget fails, do not ship until fixed or formally waived with documented rationale.

## CI Smoke Gate

CI must run:

1. Build verification.
2. Launch performance test.
3. Resume/core interaction perf smoke tests.

If smoke tests fail, treat the PR as blocked until performance is investigated.
