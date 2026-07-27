# SleepDaddy

**SleepDaddy** is a native, read-only iOS application built in SwiftUI for inspecting HealthKit sleep data at greater detail than Apple Health currently allows.

Its primary experience is a zoomable, pannable sleep-stage timeline supported by multi-night navigation, explicit HealthKit source filtering, local record exclusions, adaptive night boundaries, and current-view image sharing.

## Key Features

- **Zoomable Sleep Timeline**: Continuous stepped path representation of sleep stage intervals (`Awake`, `REM`, `Core`, `Deep`, `Asleep Unspecified`, `In Bed`) rendered cleanly over customizable viewports.
- **Maps-Style Direct Manipulation**: Smooth, high-performance timeline canvas with anchored pinch-to-zoom, low-latency continuous panning, and velocity-based spring inertia (disabled under Reduce Motion).
- **Compact Night Navigation**: Date header with edge-to-edge swipe gestures, date picker sheet, and directional navigation buttons for quick traversal across nights.
- **Smart Populated Startup**: Opens automatically to the newest night containing eligible sleep data for immediate inspection.
- **Slim Context Navigator**: Minimal mini-map track showing core sleep window boundaries and active viewport placement within full night bounds.
- **Explicit Source Filtering**: Select which HealthKit data sources (e.g. Apple Watch, Oura, Sleep Cycle) contribute to the timeline.
- **Brief Awake Filtering**: Optionally hide awake intervals of one minute or less from the timeline, for trackers that emit many short awake samples. Drawing only — sleep, awake, and stage totals are always reported from the unfiltered data.
- **Adaptive Night Boundaries**: Automatically expands core window boundaries (default 7:00 PM to 7:00 AM) to include contiguous sleep sessions while keeping disconnected naps out.
- **Local Record Exclusions**: Exclude suspicious or bad records locally without modifying or deleting data from HealthKit.
- **Viewport Image Sharing**: Render and export the visible timeline viewport as a clean image for sharing via the system share sheet.
- **100% Read-Only & Local**: No accounts, cloud sync, analytics, or HealthKit writes.

## Tech Stack & Architecture

- **Language**: Swift 6
- **UI Framework**: Native SwiftUI
- **Minimum Target**: iOS 26.0
- **Project Generator**: [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`)
- **Testing**: Swift Testing framework (`import Testing`)

### Core Architecture Components

- `HealthKitSleepStore`: Read-only HealthKit interaction layer (conforms to `HealthKitSleepStoreProtocol`).
- `SleepNormalizer`: Maps raw HealthKit category samples to application-owned `NormalizedSleepInterval` records.
- `NightAssembler`: Groups normalized intervals around core windows, applies adaptive boundary logic, filters sources/exclusions, and resolves timeline conflicts.
- `SleepTimelineGeometry`: Pure date-to-pixel coordinate calculator handling layout, pinch zoom, panning, clamping, and hit testing.
- `NightBrowserModel`: `@Observable` main view model coordinating authorization, night selection, viewport bounds, and exclusions.
- `SleepShareRenderer`: Renders `ShareTimelineCardView` into a high-resolution raster image via SwiftUI `ImageRenderer`.

## Getting Started

### Prerequisites

- macOS with Xcode 27+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed (`brew install xcodegen`)

### Building the Project

1. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```
2. Open `SleepDaddy.xcodeproj` in Xcode or build via command line:
   ```bash
   xcodebuild build -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
   ```

### Running Unit Tests

Run the unit test suite using Swift Testing:
```bash
xcodebuild test -scheme SleepDaddy -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ./DerivedData
```

## License

Copyright © 2026. All rights reserved.
