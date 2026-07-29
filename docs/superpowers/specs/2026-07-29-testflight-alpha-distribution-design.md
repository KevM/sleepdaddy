# TestFlight Alpha Distribution Design

## Goal

Automatically attach each successfully uploaded SleepDaddy build to the existing internal
TestFlight group named `Alpha`.

## Design

Keep Fastlane responsible for the complete TestFlight release sequence. The `ios beta` lane
will continue authenticating, installing read-only Match signing assets, archiving, and
uploading the app. After upload, Fastlane will wait for App Store Connect to finish processing
the build and then associate it with the `Alpha` beta group.

The lane will pass `groups: ["Alpha"]` to `upload_to_testflight` and will no longer set
`skip_waiting_for_build_processing: true`. `distribute_external` remains false, so Alpha is
treated as an internal testing group and the build is not submitted for external beta review.

## Failure Behavior

The release job fails if processing fails, times out, or no group named exactly `Alpha` exists.
This prevents a green deployment run from silently leaving testers without the new build.
Fastlane and GitHub Actions must not log secret values.

## Verification

- Add a focused static regression check that requires the `Alpha` group and rejects
  `skip_waiting_for_build_processing: true` in the beta lane.
- Verify the Fastfile parses with the locked Fastlane bundle.
- Run the existing release-script and workflow syntax checks.
- Do not upload another build during local verification.

## Current Build

Build `1.0.2 (2)` was uploaded before this change and must be added to Alpha manually once.
The automation applies to subsequent builds.
