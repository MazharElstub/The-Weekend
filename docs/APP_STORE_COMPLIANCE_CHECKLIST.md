# App Store Compliance Checklist

Use this checklist before every TestFlight/App Store submission.

## Required Pre-Submit Checks

1. Account creation is available only with a matching account deletion path.
2. Guideline 5.1.1(v) flow works in release candidate build:
   - Open `Settings`.
   - Open `Account`.
   - Tap `Delete account`.
   - Confirm both ownership-mode choice and final destructive confirmation appear.
3. Account deletion is full deletion (not deactivation only).
4. Deletion completes in-app without requiring email or phone support.
5. If user owns shared calendars:
   - Transfer mode transfers ownership when an eligible member exists.
   - Delete mode removes owned shared calendars and creates in-app notices for affected members.
6. Post-delete validation:
   - User is signed out.
   - Session cannot be re-used.
   - Account cannot sign back in.
7. Automated tests pass, including account deletion and notice parsing tests.

## Manual QA Script

1. Create Account A and Account B.
2. Join both accounts to a shared calendar owned by Account A.
3. As Account A, run delete flow in `transfer` mode.
4. Verify Account B still has the calendar and now owns it.
5. Recreate shared setup.
6. As Account A, run delete flow in `delete` mode.
7. Verify shared calendar is removed for Account B.
8. Verify Account B sees an in-app notice explaining removal reason.

## App Review Response Template

Use this in App Store Connect when responding to Guideline 5.1.1(v):

> Account deletion is available directly in-app.
> Path: `Settings` -> `Account` -> `Delete account`.
> The flow includes two confirmations and performs permanent account/data deletion in-app.
> For shared calendars owned by the deleting user, the app offers transfer of ownership or deletion with in-app notices to affected members.

## Release Gate

Do not submit unless every required check above is complete and signed off in PR notes.
