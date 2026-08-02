# SleepDaddy Website Refinements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve all code review feedback for `web/` including multi-source timeline rendering ("All Sources" rendering both Apple Watch + Oura lanes), bounded panning/zooming, matching static HTML stats, mobile `touch-action: none` / wheel zoom handling, accessibility attributes, requestAnimationFrame performance optimization, XSS-safe tooltips, Open Graph tags, GitHub Actions Pages deployment workflow (`.github/workflows/deploy-pages.yml`), and email support fallback.

**Architecture:** Vanilla HTML5/CSS3/ES6 JS enhancements in `web/` plus GitHub Actions workflow configuration.

**Tech Stack:** HTML5, CSS3, ES6 JavaScript (HTML5 2D Canvas), GitHub Actions.

## Global Constraints

- Target directory: `web/` and `.github/workflows/`
- Zero npm/runtime build dependencies.
- Retain dark obsidian theme (`#050714`), sleep stage colors, and responsive layouts down to 320px.

---

### Task 1: Multi-Source Canvas Rendering, Bounded Panning & Performance (`web/timeline-simulator.js`)

**Files:**
- Modify: `web/timeline-simulator.js`

- [ ] **Step 1: Fix "All Sources" rendering to display both Apple Watch and Oura Ring lanes**

Update `getVisibleIntervals()` in `web/timeline-simulator.js`:
When `this.activeSource === 'all'`, return all dataset intervals (both `apple_watch` and `oura`).
Update `render()` to draw source lanes / distinct vertical stage bands or stacked interval bars for multi-source visualization when `'all'` is selected, allowing visitors to inspect Apple Watch and Oura Ring side-by-side.

- [ ] **Step 2: Add Bounded Panning and Clamped Zooming**

Clamp `viewStartTime` and `viewEndTime` to `[nightStart - 15 * 60 * 1000, nightEnd + 15 * 60 * 1000]` in drag pan, touch drag, wheel zoom, and zoom button handlers. Prevent panning into infinite empty space.

- [ ] **Step 3: Coalesce mousemove redraws with `requestAnimationFrame` & skip redundant renders**

Add `this.rafPending` flag. On `mousemove`, compute hit-test for `hoveredInterval`. If `hoveredInterval` hasn't changed and not dragging, skip `this.render()`.
Add `destroy()` method to clean up `window` and `canvas` event listeners.

- [ ] **Step 4: Make hover tooltip XSS-safe**

Refactor hover tooltip builder from `innerHTML` string concatenation to DOM node creation using `textContent` and standard element setters.

- [ ] **Step 5: Test JS file syntax**

Run: `node -c web/timeline-simulator.js`
Expected: 0 syntax errors.

- [ ] **Step 6: Commit**

```bash
git add web/timeline-simulator.js
git commit -m "fix(web): render all sources in timeline, clamp panning/zooming bounds, optimize RAF redraws, and sanitize tooltips"
```

---

### Task 2: CSS Touch Action, Wheel Behavior, Responsive Header & Clean Styles (`web/index.css`)

**Files:**
- Modify: `web/index.css`

- [ ] **Step 1: Add `touch-action: none` for canvas wrapper and canvas**

Add `.simulator-canvas-wrapper, #simulator-canvas { touch-action: none; }` to prevent canvas touch dragging from scrolling/zooming the main webpage on mobile devices.

- [ ] **Step 2: Refactor inline styles into stylesheet classes**

Extract inline `style="..."` attributes from `index.html`, `privacy.html`, and `support.html` into CSS classes in `index.css` (`.stage-legend-title`, `.btn-sm`, `.stat-card-value`, `.doc-code-pill`, etc.).

- [ ] **Step 3: Polish mobile responsive breakpoint for 375px / 320px screens**

Improve `.site-header`, `.nav-container`, `.logo`, and `.nav-links` layout for narrow mobile screens so logo, navigation, and CTA button fit comfortably without wrapping artifacts.

- [ ] **Step 4: Commit**

```bash
git add web/index.css
git commit -m "fix(web): add touch-action none for canvas, extract inline styles, and polish narrow mobile header layout"
```

---

### Task 3: Accessibility, Matching Placeholder Stats, OG Meta Tags & Typos (`web/index.html`, `web/privacy.html`, `web/support.html`)

**Files:**
- Modify: `web/index.html`
- Modify: `web/privacy.html`
- Modify: `web/support.html`

- [ ] **Step 1: Fix Accessibility attributes across HTML pages**

- Canvas: Add `role="img"`, `aria-label="Interactive Sleep Stage Timeline Canvas displaying sleep stage intervals over time"`, and accessible text fallback inside `<canvas id="simulator-canvas">`.
- Source Filter: Add `<label for="source-filter" class="sr-only">Data Source</label>` and `aria-label="Filter HealthKit Data Source"`.
- Zoom buttons: Add `aria-label="Zoom in on sleep timeline"` and `aria-label="Zoom out on sleep timeline"`.

- [ ] **Step 2: Update static placeholder statistics in `index.html`**

Align static HTML placeholder stats with actual dataset output: `8h 28m` Total Sleep, `2h 05m (24.6%)` Deep, `2h 40m (31.5%)` REM, `3h 43m (43.9%)` Core, `32m` Awake to eliminate layout shifts or stale data.

- [ ] **Step 3: Add Open Graph & Twitter Card metadata**

Add `<meta property="og:title">`, `<meta property="og:description">`, `<meta property="og:image" content="app-icon.png">`, `<meta property="og:type" content="website">`, `<meta name="twitter:card" content="summary_large_image">` to `index.html`, `privacy.html`, and `support.html`.

- [ ] **Step 4: Fix typo & add email support fallback in `support.html`**

- Fix typo in `support.html`: change `"open open-source"` to `"open-source"`.
- Add email support fallback link (`support@sleepdaddy.app`) alongside GitHub Issues link.

- [ ] **Step 5: Commit**

```bash
git add web/index.html web/privacy.html web/support.html
git commit -m "fix(web): add accessibility attributes, matching stat placeholders, OG meta tags, email support fallback, and fix typo"
```

---

### Task 4: GitHub Actions Deployment Workflow (`.github/workflows/deploy-pages.yml`)

**Files:**
- Create: `.github/workflows/deploy-pages.yml`

- [ ] **Step 1: Create `.github/workflows/deploy-pages.yml`**

Create GitHub Actions workflow that automatically deploys `web/` to GitHub Pages upon push to `main` or manual dispatch using official GitHub Actions (`actions/checkout@v4`, `actions/upload-pages-artifact@v3`, `actions/deploy-pages@v4`).

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/deploy-pages.yml
git commit -m "ci: add GitHub Actions workflow to deploy web directory to GitHub Pages"
```
