# Pulse Oximeter Integration Design

**Project:** SleepDaddy
**Scope:** Selected-night detail timeline, CSV import, local vitals storage
**Status:** Approved

## Summary

SleepDaddy renders HealthKit sleep stages. It has no view of what the body was doing
during those stages. A Wellue Checkme O2 Max wrist oximeter records SpO₂, pulse rate,
and motion continuously at a two-second cadence and exports them as CSV from the
ViHealth companion app.

Import those recordings and draw them as lanes beneath the existing sleep-stage plot,
sharing a single time axis so pinch and pan move all lanes together. A dedicated rail
marks oxygen desaturation events so clusters are visible before any chart is read.

The reference export used throughout this document covers 2026-08-03 18:02:48 to
2026-08-04 06:24:54: 22,263 samples across two files, SpO₂ ranging 73–99%, pulse
ranging 32–109 bpm.

## Goals

- Draw SpO₂ and pulse rate on the same time axis as the sleep-stage plot.
- Preserve every recorded sample; reduce only what is drawn, never what is stored.
- Guarantee that brief, severe desaturations remain visible at every zoom level.
- Make desaturation events findable without reading the charts.
- Import CSV exports without preprocessing or a manual night-assignment step.
- Join recordings split by the device's ten-hour session cap into one continuous session.
- Leave HealthKit access read-only and `NightAssembler` untouched.
- Keep storage behind a protocol so iCloud durability is a later conformance, not a rewrite.

## Non-Goals

- Writing any data to HealthKit.
- Reading SpO₂ or heart rate from HealthKit. The CSV export is the only source; the
  fidelity that makes this feature worthwhile does not survive HealthKit's summarization.
- Vitals in the multi-night overview strip or the shared image card.
- Clinical interpretation, diagnosis, scoring, or advice of any kind.
- User-configurable event thresholds.
- A Share Extension target. See [Share Sheet Registration](#share-sheet-registration).
- iCloud synchronization.

## Source Data

The Checkme O2 Max export is a six-column CSV:

```
Time,Oxygen Level,Pulse Rate,Motion,O2 Reminder,PR Reminder
18:02:48 Aug 03 2026,96,109,86,0,0
```

Properties confirmed against the reference export:

| Property | Value |
| --- | --- |
| Cadence | Exactly 2 s, zero jitter across all 22,263 samples |
| Timestamp format | `HH:mm:ss MMM dd yyyy`, **no timezone or offset** |
| Missing readings | `--` sentinel in `Oxygen Level` and `Pulse Rate` together |
| Session cap | 18,000 samples (10 h 00 m 00 s), then the device opens a new file |
| Value ranges | SpO₂ 0–100, pulse 0–255, motion 0–255 — all fit in a byte |
| Reminder columns | Present but zero throughout; alarms were disabled |

The two reference files are contiguous: the first ends at 04:02:46 and the second begins
at 04:02:50, a single missed sample slot. They are one night's recording, not two.

## Architecture

Vitals resolve in parallel with sleep, never through it:

```
NightBrowserModel
├── NightAssembler   → AssembledNight    (sleep — unchanged)
└── VitalsStore      → VitalsSession?    (vitals — new, keyed by night)
                              │
                              ▼
        both handed to SelectedNightDetailView, both drawn through
        the same SleepTimelineGeometry instance
```

`NightAssembler` is not modified. Its 315 lines group sleep intervals, resolve
source conflicts, and compute summaries; vitals participate in none of that. Threading a
vitals store through it would join two concerns that have no reason to know about
each other.

Because both lanes read x-coordinates from one `SleepTimelineGeometry` instance, they
stay locked together through pinch and pan with no synchronization code. There is no
second viewport to keep in step.

## Data Model

Three types in `SleepDaddy/Models/`.

### VitalsSession

Stores samples **columnar** — three `[UInt8]` arrays rather than an array of structs:

```swift
public struct VitalsSession: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let startDate: Date
    public let sampleInterval: TimeInterval   // 2.0
    public let spo2: [UInt8]                  // 0 == missing
    public let pulse: [UInt8]                 // 0 == missing
    public let motion: [UInt8]
    public let sourceFileNames: [String]
}
```

Two consequences follow from the perfectly regular cadence:

- **No per-sample timestamp.** Sample *i* occurs at `startDate + i × sampleInterval`.
  Mapping a viewport to a sample range is arithmetic, not a search.
- **Size.** Three bytes per sample puts a twelve-hour night at roughly 66 KB, against
  roughly 1 MB as timestamped JSON. This is the one place the design trades a little
  directness for a fifteenfold reduction, and it is chosen deliberately because iCloud
  durability is a stated future goal.

`0` encodes a missing reading, which is unambiguous: a live oximeter never reports zero
saturation or zero pulse for a subject it is reading.

### Supporting types

```swift
public struct DesaturationEvent: Identifiable, Hashable, Sendable {
    public var id: Date { startDate }
    public let startDate: Date
    public let endDate: Date
    public let nadir: UInt8
    public let baseline: UInt8
    public var dropAmount: Int { Int(baseline) - Int(nadir) }
}

public struct VitalsEnvelope: Sendable {
    public struct Column: Sendable {
        public let spo2Min: UInt8?
        public let spo2Max: UInt8?
        public let pulseMin: UInt8?
        public let pulseMax: UInt8?
    }
    public let columns: [Column]
}
```

`VitalsEnvelope` is render output, never persisted.

## Rendering

### The envelope guarantee

A twelve-hour night is 22,263 samples. An iPhone timeline is roughly 1,200 points wide.
About seventeen samples therefore share each pixel column, and most cannot be drawn.

**Averaging them is not acceptable.** The reference night's worst event — SpO₂ reaching
73% at 23:07:48, lasting about 38 seconds — is nineteen samples. Averaged against the
95% readings surrounding it, that column renders near 91% and the event disappears into
an unremarkable wobble.

`VitalsEnvelopeBuilder` therefore keeps **both extremes** per column and draws the band
between them. Cost is identical; the 73% sample is drawn at 73%. Zooming out narrows an
event's width but never softens its depth.

This is the feature's load-bearing property. Everything else here is ordinary code.

### Viewport-driven, not import-driven

The envelope is computed **per frame from the complete sample array**, using the current
viewport. Nothing is discarded at import; only drawing is reduced. Zooming in resolves
the same underlying samples into more detail until, past roughly one sample per point,
individual two-second readings are drawn directly.

At 22k samples a full scan per frame is inexpensive, so there is no resolution pyramid,
no tile cache, and no background indexing. Should a future multi-night view make this
cost real, a cache goes behind `VitalsEnvelopeBuilder` without touching callers.

### Gaps

A missing reading is drawn as a **break in the line**, never interpolated across. A gap
means the sensor was not reading, which is information the viewer needs.

### Lane composition

Beneath the existing sleep-stage plot, in order:

1. **Desaturation rail** — a thin rail marking events, directly under the stage plot so
   clusters register before either chart is read.
2. **SpO₂ lane** — envelope band, scaled 70–100%, with a reference line at 88%.
3. **Pulse lane** — envelope band, scaled 30–110 bpm.

When a night has no vitals, all three are **absent entirely** — no placeholder, no empty
chrome. The app is visually identical to today.

`SleepTimelineGeometry` supplies x-coordinates unchanged. A new `VitalsLaneGeometry`
handles only value-to-y scaling, which the existing geometry has no concept of.

## Timeline Extent

`AssembledNight.timelineStart` and `timelineEnd` currently take the configured core
window as a floor, so a night is pannable across 19:00–07:00 even when sleep occupied
only part of it. The reference recording begins at 18:02, 57 minutes before that floor,
and would fall outside the timeline entirely — losing the pre-sleep waking baseline that
gives the overnight drops their reference point.

**The extent becomes data-defined:**

```
timelineStart = earliest of (detected sleep span, vitals session start)
timelineEnd   = latest   of (detected sleep span, vitals session end)
```

`preferredViewportStart` and `preferredViewportEnd` are **unchanged**, so the timeline
still opens on the detected sleep span exactly as it does today. Only the pannable
extent changes.

### Deliberate behavior change

The core window no longer influences the timeline extent for **any** night, including
nights with no vitals. A night with sleep from 23:00 to 06:00 previously allowed panning
back to 19:00 across empty evening; it now bounds to the data.

The core window keeps its **other** responsibility unchanged: selecting which intervals
seed a night in `NightAssembler`. These are two distinct jobs that happen to share a
configured value today; only the extent job is being removed.

`NightAssemblerTests` and `SleepTimelineGeometryTests` carry expectations that encode the
old floor. Updating them is part of this work and is an intended consequence, not
incidental churn.

## Import

### Pipeline

```
CSV file
  → CheckmeCSVParser        (text → VitalsSession; pure, no I/O)
  → VitalsSessionStitcher   (join files within 5 min of each other)
  → VitalsStore             (persist)
```

Import is one-way. Rendering never touches files.

### Session stitching

Recordings whose boundaries fall within **five minutes** of each other join into a single
session. The reference files' four-second gap qualifies comfortably; a genuine second
recording, hours later, does not.

### Night matching

Sessions bind to nights automatically by timestamp overlap against
`AssembledNight.detectedStart`/`detectedEnd`. There is no manual assignment step.

### Storage

`FileVitalsStore` writes binary property lists into Application Support, one file per
session. `VitalsStore` is a protocol; iCloud durability later is a new conformance, and
callers do not change.

### Share Sheet Registration

Two mechanisms exist and only one is reliable.

**In scope — document types.** `project.yml` declares `CFBundleDocumentTypes` with
`LSItemContentTypes = ["public.comma-separated-values-text"]` and
`LSSupportsOpeningDocumentsInPlace`. This registers SleepDaddy as a CSV handler, giving
**"Open in SleepDaddy"** in the share sheet's action list and enabling the Files picker
path. It is a manifest edit plus an `onOpenURL` handler.

**Deferred — Share Extension.** Appearing as a first-class destination in the share
sheet's app icon row requires a separate extension target with an
`NSExtensionActivationRule` predicate. Because an extension runs in its own process, it
cannot write to the app container directly; it needs an App Group shared container and a
handoff path, adding a second place import can fail.

The deferral is a sequencing judgment, not a rejection. Document types are needed
regardless and cost almost nothing. Until ViHealth's actual export behavior is observed,
it is unknown whether an extension is needed at all — if ViHealth hands off a file URL
through a standard share sheet, "Open in SleepDaddy" is sufficient. **Decision point:**
after document types ship, export a recording from ViHealth and inspect the share sheet.
Build the extension only if SleepDaddy does not appear usefully.

## Desaturation Detection

`DesaturationDetector` walks the session with a rolling baseline — the maximum SpO₂ over
the preceding 120 seconds — and opens an event when a reading falls at least **4%** below
it, closing when it recovers. Each event records its nadir, baseline, and duration.

The rail marks events reaching **below 88%**.

Both thresholds are fixed constants in v1, expressed as named values so exposing them in
`SleepPreferences` later is mechanical.

These are conventional signal-processing parameters for making events visible on a chart.
They are **not** a clinical scoring implementation, and nothing in the app interprets,
grades, or characterizes what it draws.

## Error Handling

| Condition | Behavior |
| --- | --- |
| Malformed CSV | Typed `VitalsImportError` naming the offending line. Import fails whole; never a silent partial |
| Unrecognized header | Rejected with a clear message; no guessing at column order |
| `--` readings | Stored as `0`, drawn as a gap, excluded from events and envelope extremes |
| Duplicate import | Deduplicated on `(startDate, sampleCount)`; re-importing is a no-op |
| Session overlapping no night | Retained in the store, drawn on whichever night it overlaps once one exists |
| Night with no vitals | Lanes absent entirely |

### Timezone

The CSV carries **no timezone**. Timestamps are interpreted in the device's current zone.
This is correct for the ordinary case and wrong in two known ones: importing a recording
made in a different timezone, and importing across a daylight-saving transition. Either
can place a session up to an hour off against HealthKit samples, which are absolute
instants.

This is an accepted v1 limitation, recorded here rather than defended against. The
mitigation, if it becomes real, is a per-session timezone override at import.

## Testing

Swift Testing throughout, per `AGENTS.md`. Fixtures are trimmed from the reference export.

**`CheckmeCSVParserTests`** — well-formed parse; `--` in both columns; malformed rows;
unrecognized headers; the exact 18,000-row session cap; timestamp parsing across the
midnight rollover present in the reference data.

**`VitalsSessionStitcherTests`** — the reference four-second gap joins into one session; a
forty-minute gap stays two; three-file chains; out-of-order input.

**`VitalsEnvelopeBuilderTests`** — the critical suite. A single 73% sample must still read
73% after reduction to 100 columns, to 10 columns, and to 1. Gaps must not be bridged.
Empty viewports must not crash. **This suite is what prevents the feature from ever
quietly understating the worst moment of a night.**

**`DesaturationDetectorTests`** — known event counts against the fixture; synthetic ramps
with hand-computed expectations; gap regions produce no events.

**`VitalsLaneGeometryTests`** — value-to-y scaling, clamping beyond range, and agreement
with `SleepTimelineGeometry` on x for identical viewports.

**`NightAssemblerTests` / `SleepTimelineGeometryTests`** — updated for the data-defined
extent described above.

No pixel-snapshot tests. The lane is verified by a SwiftUI preview driven by the real
fixture.

## Project Changes

`project.yml` gains `UniformTypeIdentifiers` and the CSV document type declaration.
Regenerate with `xcodegen generate`; neither `SleepDaddy.xcodeproj` nor generated
`Info.plist` files are committed.

HealthKit usage is unchanged and remains read-only.

## Scope Boundary

In scope: CSV import via Files and "Open in", stitching, local storage, the three lanes
on the selected-night detail timeline, desaturation detection, and the data-defined
timeline extent.

Out of scope for v1: iCloud, the Share Extension, vitals in the multi-night strip or
share card, configurable thresholds, HealthKit vitals, and any interpretation of the
data beyond drawing it.
