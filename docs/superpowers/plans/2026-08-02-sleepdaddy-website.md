# SleepDaddy Website Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a modern dark ambient website for the SleepDaddy iOS app inside `web/` featuring a high-definition interactive sleep timeline simulator, feature showcase, privacy policy, and support pages.

**Architecture:** Built using zero-dependency vanilla HTML5, CSS3, and ES6 JavaScript. The interactive simulator uses an HTML5 Canvas engine with anchored zoom/pan, tooltip inspection, source filtering, and brief awake spike smoothing.

**Tech Stack:** HTML5, CSS3 (CSS Variables, Flexbox/Grid, Glassmorphism, Backdrop Filters), ES6 JavaScript (HTML5 2D Canvas Context).

## Global Constraints

- Target directory: `web/`
- Zero runtime npm/build dependencies — standard vanilla web standards.
- Dark ambient color palette: Base `#050714`, Card glass `rgba(15, 23, 42, 0.65)`, Glow `#6366f1` / `#8b5cf6`.
- Sleep stage color tokens: Awake (`#fbbf24`), REM (`#818cf8`), Core (`#3b82f6`), Deep (`#8b5cf6`).
- Fully responsive across desktop, tablet, and mobile screens (minimum 360px width).

---

### Task 1: Core Design System & CSS Stylesheet (`web/index.css`)

**Files:**
- Create: `web/index.css`

**Interfaces:**
- Produces: CSS custom properties (`:root`), typography styling, glassmorphism utilities, grid layouts, button components, and canvas simulator container styles used by `index.html`, `privacy.html`, `support.html`, and `timeline-simulator.js`.

- [ ] **Step 1: Create `web/index.css` with CSS custom variables and reset**

```css
:root {
  --bg-dark: #050714;
  --bg-surface: rgba(15, 23, 42, 0.65);
  --bg-surface-hover: rgba(30, 41, 59, 0.8);
  --border-glass: rgba(255, 255, 255, 0.08);
  --border-highlight: rgba(129, 140, 248, 0.3);
  
  --text-main: #f8fafc;
  --text-muted: #94a3b8;
  --text-subtle: #64748b;
  
  --accent-primary: #6366f1;
  --accent-secondary: #8b5cf6;
  --accent-glow: rgba(99, 102, 241, 0.25);

  --stage-awake: #fbbf24;
  --stage-rem: #818cf8;
  --stage-core: #3b82f6;
  --stage-deep: #8b5cf6;
  --stage-unspecified: #64748b;

  --font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  --max-width: 1200px;
  --radius-lg: 16px;
  --radius-md: 10px;
  --radius-sm: 6px;
}

* {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}

body {
  background-color: var(--bg-dark);
  color: var(--text-main);
  font-family: var(--font-family);
  line-height: 1.6;
  overflow-x: hidden;
}
```

- [ ] **Step 2: Add navigation, hero glow, badge, buttons, feature grid, and simulator styles to `web/index.css`**

Add container, header nav, `.hero-glow`, `.badge`, `.btn-primary`, `.btn-secondary`, `.simulator-container`, `.feature-card`, `.cta-box`, and media queries `@media (max-width: 768px)` to `web/index.css`.

- [ ] **Step 3: Verify CSS syntax and structure**

Run: `ls -lh web/index.css`
Expected: File `web/index.css` exists with complete styling definitions.

- [ ] **Step 4: Commit**

```bash
git add web/index.css
git commit -m "feat(web): add core CSS design system for SleepDaddy website"
```

---

### Task 2: Interactive Sleep Timeline Canvas Engine (`web/timeline-simulator.js`)

**Files:**
- Create: `web/timeline-simulator.js`

**Interfaces:**
- Consumes: Container DOM element `#simulator-canvas` and controls HUD elements in `index.html`.
- Produces: `SleepTimelineSimulator` class managing interactive 2D canvas rendering, drag-to-pan, pinch/wheel zoom, stage tooltips, source filtering, brief awake spike toggling, and live statistics update.

- [ ] **Step 1: Define `SleepTimelineSimulator` class and synthetic dataset in `web/timeline-simulator.js`**

```javascript
class SleepTimelineSimulator {
  constructor(canvasId, statsContainerId) {
    this.canvas = document.getElementById(canvasId);
    if (!this.canvas) return;
    this.ctx = this.canvas.getContext('2d');
    this.statsContainer = document.getElementById(statsContainerId);

    // Initial time range: 10:15 PM to 7:15 AM
    this.baseStartTime = new Date(2026, 7, 1, 22, 15).getTime();
    this.baseEndTime = new Date(2026, 7, 2, 7, 15).getTime();

    this.viewStartTime = this.baseStartTime;
    this.viewEndTime = this.baseEndTime;

    this.activeSource = 'all'; // 'all', 'apple_watch', 'oura'
    this.hideBriefAwake = false;

    this.intervals = this.generateSampleData();
    this.isDragging = false;
    this.dragStartX = 0;
    this.hoveredInterval = null;

    this.init();
  }

  generateSampleData() {
    // Stage enum: 'awake', 'rem', 'core', 'deep'
    return [
      { start: '22:15', end: '22:30', stage: 'awake', source: 'apple_watch' },
      { start: '22:30', end: '23:15', stage: 'core', source: 'apple_watch' },
      { start: '23:15', end: '23:45', stage: 'deep', source: 'apple_watch' },
      { start: '23:45', end: '23:46', stage: 'awake', source: 'apple_watch' }, // Brief 1m awake
      { start: '23:46', end: '00:30', stage: 'deep', source: 'apple_watch' },
      { start: '00:30', end: '01:15', stage: 'rem', source: 'oura' },
      { start: '01:15', end: '02:30', stage: 'core', source: 'apple_watch' },
      { start: '02:30', end: '03:10', stage: 'deep', source: 'oura' },
      { start: '03:10', end: '04:15', stage: 'rem', source: 'apple_watch' },
      { start: '04:15', end: '04:16', stage: 'awake', source: 'oura' }, // Brief 1m awake
      { start: '04:16', end: '05:30', stage: 'core', source: 'apple_watch' },
      { start: '05:30', end: '06:35', stage: 'rem', source: 'apple_watch' },
      { start: '06:35', end: '07:15', stage: 'awake', source: 'apple_watch' }
    ];
  }

  // ... implementation of render(), pan(), zoom(), hitTest(), calcStats()
}
```

- [ ] **Step 2: Implement canvas drawing, coordinate mapping, event listeners, and UI HUD binding**

Implement date-to-pixel mapping, stepped path drawing for stages (Awake=top, REM=upper mid, Core=lower mid, Deep=bottom), hover inspection tooltip, panning via drag, zoom via wheel/buttons, source filtering, and stats update.

- [ ] **Step 3: Verify JS script initialization**

Run: `node -c web/timeline-simulator.js`
Expected: Syntax clean, no syntax errors.

- [ ] **Step 4: Commit**

```bash
git add web/timeline-simulator.js
git commit -m "feat(web): add interactive sleep timeline simulator canvas engine"
```

---

### Task 3: Main Landing Page (`web/index.html`)

**Files:**
- Create: `web/index.html`

**Interfaces:**
- Consumes: `web/index.css`, `web/timeline-simulator.js`
- Produces: Complete SleepDaddy landing page with navigation, hero section, interactive simulator, 6 feature cards, architecture spotlight, TestFlight download section, and footer.

- [ ] **Step 1: Create `web/index.html` structure with head metadata and header navigation**

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="description" content="SleepDaddy — High-definition native iOS sleep stage timeline inspector for HealthKit. Deep zooming, multi-source filtering, adaptive night boundaries, and local record exclusions.">
  <meta name="theme-color" content="#050714">
  <title>SleepDaddy — High-Definition HealthKit Sleep Inspector</title>
  <link rel="stylesheet" href="index.css">
</head>
<body>
  <!-- Background Glows -->
  <div class="hero-glow"></div>

  <!-- Header -->
  <header>
    <div class="container nav-container">
      <a href="#" class="logo">
        <svg width="32" height="32" viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <linearGradient id="logo-grad" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stop-color="#6366f1" />
              <stop offset="100%" stop-color="#8b5cf6" />
            </linearGradient>
          </defs>
          <rect x="2" y="2" width="28" height="28" rx="8" fill="url(#logo-grad)" />
          <path d="M9 20 C12 14, 20 14, 23 20" stroke="#ffffff" stroke-width="2.5" fill="none" stroke-linecap="round" />
          <circle cx="11" cy="11" r="2" fill="#ffffff" />
          <circle cx="21" cy="11" r="2" fill="#ffffff" />
        </svg>
        <span>SleepDaddy</span>
      </a>
      <nav class="nav-links">
        <a href="#features">Features</a>
        <a href="#simulator">Live Demo</a>
        <a href="privacy.html">Privacy</a>
        <a href="support.html">Support</a>
        <a href="#download" class="btn-primary">Join TestFlight</a>
      </nav>
    </div>
  </header>
```

- [ ] **Step 2: Add Hero Section, Simulator Container, Feature Grid, Privacy Spotlight, TestFlight CTA, and Footer**

Include the interactive simulator HUD (`#simulator`), feature grid with 6 cards, privacy architecture spotlight, TestFlight download callout box, and script tag `<script src="timeline-simulator.js"></script>`.

- [ ] **Step 3: Validate HTML markup and structure**

Run: `ls -lh web/index.html`
Expected: `web/index.html` created successfully.

- [ ] **Step 4: Commit**

```bash
git add web/index.html
git commit -m "feat(web): add main landing page index.html with interactive hero simulator"
```

---

### Task 4: Supporting Pages (`web/privacy.html` & `web/support.html`)

**Files:**
- Create: `web/privacy.html`
- Create: `web/support.html`

**Interfaces:**
- Consumes: `web/index.css`
- Produces: Dedicated privacy agreement page and support/FAQ page.

- [ ] **Step 1: Create `web/privacy.html`**

Write `privacy.html` detailing:
- 100% Read-Only HealthKit access policy.
- Zero cloud transmission or server storage.
- Local storage details (`UserDefaults` / `PreferencesStore`).
- User rights and complete data privacy control.

- [ ] **Step 2: Create `web/support.html`**

Write `support.html` providing:
- Getting Started with SleepDaddy guide.
- HealthKit permissions troubleshooting.
- Source selection & filtering FAQ.
- Brief awake spike toggle explanations.
- Support & feedback contact links.

- [ ] **Step 3: Commit**

```bash
git add web/privacy.html web/support.html
git commit -m "feat(web): add privacy policy and support documentation pages"
```

---

### Task 5: Static Config Files & Local Server Verification

**Files:**
- Create: `web/CNAME`
- Create: `web/.gitignore`

- [ ] **Step 1: Add `web/CNAME` and `web/.gitignore`**

- [ ] **Step 2: Run local web server and verify interactive functionality**

Run: `python3 -m http.server 8080 --directory web`
Verify: `index.html`, `privacy.html`, `support.html` render cleanly, CSS glassmorphism styles apply, canvas simulator drag/zoom/tooltips/filters function smoothly.

- [ ] **Step 3: Commit**

```bash
git add web/CNAME web/.gitignore
git commit -m "feat(web): add web configuration and verify site build"
```
