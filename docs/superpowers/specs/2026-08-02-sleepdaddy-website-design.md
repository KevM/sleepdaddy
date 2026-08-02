# SleepDaddy Website Design Specification

**Date**: 2026-08-02  
**Target Directory**: `web/`  
**Tech Stack**: Vanilla HTML5, CSS3, ES6 JavaScript (Zero dependencies, dark mode ambient design)

---

## 1. Overview

SleepDaddy is a native, read-only iOS application built in SwiftUI (Swift 6) for inspecting HealthKit sleep data in high detail via a zoomable timeline, multi-night overview, source filtering, local exclusions, adaptive night boundaries, and current-view image export.

This web application serves as the official landing page and live interactive feature showcase for SleepDaddy. It adopts a modern dark ambient aesthetic (inspired by `../televista/web`) with glowing midnight gradients, glassmorphism, responsive components, and an in-browser interactive sleep timeline simulator.

---

## 2. Architecture & File Layout

All website assets reside within the `web/` directory:

```text
web/
├── index.html            # Main landing page (Hero, Interactive Simulator, Feature Cards, Architecture, Download CTA)
├── index.css             # Complete design system (Variables, Color Tokens, Glassmorphism, Responsive Grid, Animations)
├── timeline-simulator.js # Pure JS Sleep Timeline Simulator (Canvas rendering, Drag-Pan, Zoom, Stage Tooltips, Filters)
├── privacy.html          # Read-only HealthKit & Local Privacy Policy
├── support.html          # FAQ, HealthKit Permissions Guide & Support Contacts
├── CNAME                 # Custom domain configuration (if needed)
└── .gitignore            # Local web build ignores
```

---

## 3. Visual Design System

* **Color Palette**:
  * Background Base: `#050714` (Deep Midnight Obsidian)
  * Background Surface / Glass: `rgba(15, 23, 42, 0.65)` with `backdrop-filter: blur(16px)`
  * Accent Glows: `#6366f1` (Indigo), `#8b5cf6` (Purple/Violet)
  * Text Primary: `#f8fafc`
  * Text Secondary: `#94a3b8`
* **Sleep Stage Tokens**:
  * **Awake**: `#fbbf24` (Amber)
  * **REM**: `#818cf8` (Indigo)
  * **Core**: `#3b82f6` (Electric Blue)
  * **Deep**: `#8b5cf6` (Violet)
  * **In Bed / Unspecified**: `#64748b` (Slate)
* **Typography**:
  * Inter / System UI sans-serif stack with high legibility and dynamic weight hierarchy.

---

## 4. Interactive Timeline Simulator (`timeline-simulator.js`)

The hero section features a live interactive simulation of SleepDaddy's timeline:

1. **Interactive Controls HUD**:
   * **Source Filter**: `All Sources`, `Apple Watch Series 10`, `Oura Ring Gen 3`
   * **Brief Awake Filter**: Toggle `Hide Awake ≤ 1m` to demonstrate visual spike smoothing without affecting total sleep stats.
   * **Viewport Zoom & Pan**:
     * Mouse drag / touch drag for continuous horizontal panning.
     * Scroll wheel / pinch gesture for anchored viewport zooming.
     * `+` / `-` / `Reset` action buttons.
2. **Stepped Timeline Canvas**:
   * Continuous stepped path rendering sleep intervals across a 9-hour night (10:15 PM – 7:15 AM).
   * Hover/Tap tooltip displaying Stage name, Start/End timestamp, Duration, and Source tracker.
3. **Dynamic Stage Summary**:
   * Real-time calculation of stage percentages:
     * **Total Sleep**: 7h 42m
     * **Deep**: 1h 18m (17%)
     * **REM**: 1h 45m (23%)
     * **Core**: 4h 12m (55%)
     * **Awake**: 27m (5%)

---

## 5. Core Sections & Feature Showcase (`index.html`)

1. **Header Navigation**:
   * Logo icon + SleepDaddy branding
   * Links: `Features`, `Live Demo`, `Privacy`, `Support`
   * Action: `"Join TestFlight Beta"` CTA button
2. **Hero Section**:
   * Badge: `"100% Read-Only HealthKit Sleep Inspector"`
   * Headline: `"Inspect Your Sleep in High Definition"`
   * Description highlighting timeline zooming, source filtering, adaptive night boundaries, and local record exclusions.
   * Dual CTAs: `"Get TestFlight Beta"` & `"Explore Interactive Demo"`.
   * **Embedded Timeline Simulator Frame**.
3. **App Features Grid (6 Core Cards)**:
   * **Zoomable Stepped Timeline**: High-precision continuous stage pathing.
   * **Explicit Source Filtering**: Isolate data from Apple Watch, Oura, or third-party apps.
   * **Brief Awake Filtering**: Smooth away 1-minute awake noise visually.
   * **Adaptive Night Boundaries**: Dynamic core windows (default 7PM – 7AM) that auto-expand for continuous sleep.
   * **Local Record Exclusions**: Exclude bad samples locally with zero HealthKit writes.
   * **Viewport Image Export**: Export clean share cards directly to iOS Share Sheet.
4. **Privacy & Architecture Spotlight**:
   * Details on read-only HealthKit design, local-only `UserDefaults` storage, zero analytics, zero cloud transmission.
5. **Download CTA / TestFlight Banner**:
   * Callout box guiding users to TestFlight beta access.
6. **Footer**:
   * Links to Privacy, Support, GitHub, and iOS 26 / Swift 6 build badge.

---

## 6. Supporting Pages

* **`privacy.html`**: Detailed privacy policy clarifying read-only HealthKit permissions, local storage, and zero data tracking.
* **`support.html`**: Troubleshooting guide for HealthKit authorization, sleep data sync, source filtering, and contact support.

---

## 7. Verification & Testing

* Validate HTML5 markup standards across `index.html`, `privacy.html`, and `support.html`.
* Verify interactive canvas dragging, zooming, source switching, and brief awake toggling in Chrome / Safari / Firefox.
* Test responsive breakpoints (Desktop, Tablet, Mobile) down to 360px viewport width.
