# AGENTS.md - Developer & AI Pair Programming Guide

This document provides context, conventions, architecture guidelines, and standard commands for AI assistants working on **SleepDaddy**.

## Project Overview

SleepDaddy is a read-only iOS application for inspecting HealthKit sleep data in high detail via a zoomable timeline, multi-night overview, source filtering, local exclusions, adaptive night boundaries, and current-view image export.

## Key Principles & Conventions

1. **Swift 6 & Native SwiftUI**: iOS 18+ target built with modern SwiftUI and Swift 6 concurrency features. Build against the latest iOS SDK, but keep runtime API usage within iOS 18 or guard it with `@available`/`#available`.
2. **XcodeGen Managed**: Do NOT commit `SleepDaddy.xcodeproj` or `Info.plist` files. Modify `project.yml` when adding new frameworks, targets, or Info.plist configuration, then run `xcodegen generate`.
3. **Read-Only HealthKit**: HealthKit is read-only. Never add write/update code for HealthKit data. Local record exclusions and preferences are persisted locally in `UserDefaults` (`SleepPreferences` / `PreferencesStore`).
4. **Swift Testing**: Unit tests use the modern `import Testing` framework (`@Test` functions and `#expect(...)` assertions).
5. **Decoupled Geometry & Layout**: Timeline geometry calculations (dates to pixels, pinch zoom scaling, drag panning, clamping, hit testing) reside in `SleepTimelineGeometry.swift` so canvas behavior can be tested without rendering UI pixels.
6. **Generated App Icon**: `SleepDaddy/AppIcon.icon` is an Icon Composer document whose layers are rendered from the `SleepStage.themeColor` palette by `Scripts/generate-app-icon.swift`. Edit the script, not the PNGs, and re-run it to regenerate both the icon layers and the website icons. Do not commit artwork above 512px — `web/build.js` deploys everything under `web/` — pass `--master <path>` when a full-resolution render is needed. Building it needs the iOS 26 SDK or newer regardless of the deployment target; iOS versions below 26 get a flattened fallback that `actool` renders from the same layers.

## Standard Development Commands

### 1. Regenerate Xcode Project
```bash
xcodegen generate
```

### 2. Build Scheme
```bash
xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

### 3. Run Unit Test Suite
```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

### 4. Regenerate Screenshots and the Demo Video
```bash
./Scripts/capture-screenshots.sh   # App Store screenshots
./Scripts/record-demo.sh           # App Review demo video
```

Read [docs/regenerating-marketing-assets.md](docs/regenerating-marketing-assets.md)
first. The simulator's screen recorder has constraints that are not obvious and
that both scripts are built around; the doc covers them, how to verify the
output, and roughly how long to expect each pass to take.

## Directory Structure

```text
sleepdaddy/
├── project.yml                 # XcodeGen project specification
├── README.md                   # User & project documentation
├── AGENTS.md                   # AI pair programming guidelines
├── Scripts/                    # Release helpers and generate-app-icon.swift
├── SleepDaddy/
│   ├── AppIcon.icon/           # Icon Composer document (layers are generated)
│   ├── SleepDaddyApp.swift     # Main app entrypoint
│   ├── Models/                 # SleepStage, NormalizedSleepInterval, SleepPreferences, AssembledNight, NightSummary, TimelineConflict
│   ├── Services/               # HealthKitSleepStore, FixtureSleepStore, SleepNormalizer, NightAssembler, PreferencesStore
│   ├── ViewModels/             # NightBrowserModel (@Observable)
│   ├── Layout/                 # SleepTimelineGeometry
│   ├── Views/                  # ContentView, MultiNightOverviewStrip, SelectedNightDetailView, SleepTimelineCanvas, CombinedTimelineRail, IntervalInspectorSheet, SourceFilterView, SettingsView, ExcludedRecordsView, ShareTimelineCardView
│   └── Utilities/              # SleepShareRenderer, AccessibilityHelpers
└── SleepDaddyTests/            # Unit test suites (Swift Testing)
```
