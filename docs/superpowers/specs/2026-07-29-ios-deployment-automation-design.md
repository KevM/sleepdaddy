# iOS Deployment Automation

## Goal

Give SleepDaddy the same reliable delivery path as Televista: build and test every proposed
change, advance the version after each merged pull request, and archive and upload tagged or
manually dispatched builds to TestFlight.

SleepDaddy will own its automation files so the applications can evolve independently. The
only shared release resource is the existing private Fastlane `match` repository, which will
hold signing assets for both bundle identifiers.

## Architecture

Three GitHub Actions workflows divide the responsibilities:

- `.github/workflows/ci.yml` regenerates the Xcode project and runs the full test suite for
  pushes and pull requests targeting `main`.
- `.github/workflows/bump-build.yml` increments the build and patch versions after a pull
  request is merged into `main`, then commits the change back to `main`.
- `.github/workflows/release.yml` responds to `v*` tags and manual dispatches, installs the
  release toolchain and signing assets, archives SleepDaddy, uploads it to TestFlight, and
  retains the IPA and dSYMs for diagnosis.

Fastlane owns signing, archiving, and upload behavior. XcodeGen's `project.yml` remains the
source of truth for the generated project, Info.plists, versions, identifiers, entitlements,
and normal automatic-signing configuration. Generated `.xcodeproj` and Info.plist files
remain uncommitted.

## Repository Components

The implementation adds:

- A `Gemfile` and lockfile pinning Fastlane for reproducible local and CI execution.
- `fastlane/Appfile` identifying `fm.rodeo.SleepDaddy`.
- `fastlane/Matchfile` selecting the existing private signing repository and the SleepDaddy
  App Store profile.
- `fastlane/Fastfile` containing an iOS `beta` lane.
- `Scripts/bump-build-number.sh` containing the version update and validation logic.
- The three GitHub Actions workflows described above.
- Release-artifact and Fastlane-output entries in `.gitignore`.
- Setup and release documentation in `README.md`.

The Fastlane lane uses the `SleepDaddy` scheme, `fm.rodeo.SleepDaddy` bundle identifier,
`SleepDaddy.xcodeproj`, and the provisioning profile named
`match AppStore fm.rodeo.SleepDaddy`.

## Signing and TestFlight Flow

The release workflow receives the development team, App Store Connect API key, and `match`
credentials through GitHub Actions secrets. It generates the Xcode project, authenticates to
App Store Connect without interactive Apple ID or two-factor authentication, and invokes
`match` in read-only mode.

Fastlane temporarily changes the disposable generated project from automatic signing to
manual distribution signing for the archive. It uses the profile installed by `match`, builds
with the App Store export method, and uploads the archive to TestFlight without waiting for
Apple's processing to finish. Local development continues to use automatic signing.

Before the first upload:

1. The `fm.rodeo.SleepDaddy` App ID must exist in Apple Developer with HealthKit enabled.
2. A corresponding SleepDaddy application record must exist in App Store Connect.
3. The existing App Store Connect API key must have access to that application.
4. Running `bundle exec fastlane match appstore` from an authorized local machine must add a
   HealthKit-enabled SleepDaddy profile to the shared private signing repository.
5. The required GitHub Actions secrets must be configured for the SleepDaddy repository.

CI never creates, repairs, or revokes signing assets. Missing or invalid Apple-side
configuration causes the release to fail instead of mutating signing state.

## Versioning

`project.yml` gains explicit `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` values. Subject
to any pre-existing App Store version constraint, they start at `1.0.1` and `1`.

After every merged pull request, the bump workflow:

1. Increments `CURRENT_PROJECT_VERSION`.
2. Sets `MARKETING_VERSION` to `1.0.<build number>`, matching Televista's convention.
3. Validates that both replacements occurred.
4. Commits and pushes the updated `project.yml` with a skip-CI marker.

A release tag such as `v1.0.7` is expected to match the marketing version in `project.yml`.
The release workflow validates this relationship for tag-triggered releases and fails before
archiving when the values differ. Manual dispatch uses the version currently recorded in
`project.yml`.

## CI and Error Handling

CI selects an available iPhone simulator on the runner instead of relying on a hard-coded
device model. It disables code signing for simulator tests, writes an xcresult bundle, and
uploads that bundle even when tests fail.

The workflows use a macOS runner and Xcode installation that provide the iOS 26 SDK required
by SleepDaddy. They fail with actionable output if no compatible Xcode or iPhone simulator is
available.

Release concurrency permits only one archive/upload at a time without cancelling an active
release. Build artifacts are uploaded whenever available, including after a failed TestFlight
upload. Secrets are passed through the environment and are never written to committed files
or printed deliberately.

## Verification

Implementation verification covers:

- Shell checks showing that the bump script increments well-formed values and rejects missing
  or malformed version keys.
- XcodeGen generation followed by inspection of resolved scheme, bundle identifier, version,
  HealthKit entitlement, and signing build settings.
- The complete Swift Testing suite on a simulator with code signing disabled.
- Fastlane configuration parsing and a release-lane dry check that stops before upload.
- Review of workflow triggers, permissions, concurrency, secret names, and artifact paths.

The first real TestFlight upload is intentionally initiated by manual dispatch or a matching
version tag only after the Apple Developer, App Store Connect, `match`, and GitHub secret
prerequisites are complete.

## Out of Scope

This work does not automate App Store production submission, phased release, metadata,
screenshots, tester-group management, or creation of Apple Developer and App Store Connect
records. It also does not centralize Televista and SleepDaddy into a reusable cross-repository
workflow; independent copies are preferred until further duplication justifies that
abstraction.
