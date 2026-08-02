# SleepDaddy Vercel & Web Quality Refinements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refine the SleepDaddy website for deployment to Vercel via GitHub Actions (GHA). Fix deployment configs, remove unsafe query-param link rewrites, optimize image assets from 1.27MB down to a few KB, clarify multi-source stat card labeling, fix fallback URLs across pages, add Open Graph & Twitter meta tags, and set up GHA Vercel deployment workflow.

**Architecture:** Vercel deployment via GHA workflow (`.github/workflows/deploy-vercel.yml`), clean static HTML/CSS/JS in `web/` with optimized PNG icon assets.

**Tech Stack:** HTML5, CSS3, ES6 JavaScript, macOS `sips` image optimization, Vercel CLI / GitHub Actions.

## Global Constraints

- Target directory: `web/` and `.github/workflows/`
- Zero npm runtime build dependencies.
- Retain dark obsidian theme (`#050714`), sleep stage colors, and responsive layouts.

---

### Task 1: Image Optimization & Resizing (`web/app-icon.png` -> 32px / 64px / 180px)

**Files:**
- Create: `web/favicon-32x32.png`
- Create: `web/app-icon-64x64.png`
- Create: `web/app-icon-180x180.png`
- Remove / Replace: `web/app-icon.png`

- [ ] **Step 1: Generate scaled PNG assets using `sips`**

Run:
```bash
sips -z 32 32 SleepDaddy/Assets.xcassets/AppIcon.appiconset/AppIcon.png --out web/favicon-32x32.png
sips -z 64 64 SleepDaddy/Assets.xcassets/AppIcon.appiconset/AppIcon.png --out web/app-icon-64x64.png
sips -z 180 180 SleepDaddy/Assets.xcassets/AppIcon.appiconset/AppIcon.png --out web/app-icon-180x180.png
```
Verify size of generated PNGs (total ~15-20 KB vs 1.27 MB).

- [ ] **Step 2: Commit**

```bash
git add web/favicon-32x32.png web/app-icon-64x64.png web/app-icon-180x180.png
git commit -m "perf(web): generate optimized PNG icon assets (32px, 64px, 180px) replacing 1.27MB raw icon"
```

---

### Task 2: Multi-Source Stats Honesty, Security & Script Separation (`web/timeline-simulator.js` & `web/main.js`)

**Files:**
- Modify: `web/timeline-simulator.js`
- Create: `web/main.js`

- [ ] **Step 1: Clarify multi-source stat card labeling in `updateStats()`**

When `selectedSource === 'all'`, update `#stat-total` label or render a badge indicating `(Apple Watch Primary)` so visitors know the statistics describe Apple Watch data without doubling stats.

- [ ] **Step 2: Remove unsafe `?testflight=` query-param branch & separate TestFlight script**

Remove `?testflight=` query parameter handler from `timeline-simulator.js` to eliminate open-redirect / `javascript:` XSS risks.
Create `web/main.js` for site-wide UI logic (TestFlight button fallback handling, smooth scrolling).

- [ ] **Step 3: Test JS syntax**

Run: `node -c web/timeline-simulator.js && node -c web/main.js`
Expected: 0 syntax errors.

- [ ] **Step 4: Commit**

```bash
git add web/timeline-simulator.js web/main.js
git commit -m "fix(web): clarify multi-source stat card source labeling, remove unsafe query-param URL handling, and decouple site scripts"
```

---

### Task 3: HTML Markup Refinements, Open Graph Tags, Fallback Links & Image References (`web/index.html`, `web/privacy.html`, `web/support.html`)

**Files:**
- Modify: `web/index.html`
- Modify: `web/privacy.html`
- Modify: `web/support.html`

- [ ] **Step 1: Update image references to use optimized icons**

Replace `app-icon.png` references in `<head>` and `<img>` tags with `favicon-32x32.png` for favicons, `app-icon-64x64.png` for header/footer logos, and `app-icon-180x180.png` for Open Graph meta tags.

- [ ] **Step 2: Fix TestFlight fallback link and static placeholder stats formatting**

- Replace `${TESTFLIGHT_URL:-#download}` fallback with `index.html#download` across `privacy.html` and `support.html`.
- Format static HTML placeholder stats in `index.html` to match `formatDuration` output (`2h 5m` instead of `2h 05m`) to eliminate layout shift on load.

- [ ] **Step 3: Add Open Graph, Twitter Cards, Canonical URLs & Fix Typos**

- Add `<meta property="og:url" content="https://sleepdaddy.app/">`, `<link rel="canonical" href="https://sleepdaddy.app/">`, `<meta property="og:image" content="app-icon-180x180.png">`, `<meta name="twitter:card" content="summary_large_image">` to all HTML pages.
- Fix typo in `support.html`: change `"open open-source"` to `"open-source"`.

- [ ] **Step 4: Commit**

```bash
git add web/index.html web/privacy.html web/support.html
git commit -m "fix(web): update image tags to optimized icons, fix TestFlight fallback links, match stat placeholder formatting, add OG tags, and fix typo"
```

---

### Task 4: Deployment Config & GitHub Actions Vercel Deployment (`web/vercel.json`, `.github/workflows/deploy-vercel.yml`)

**Files:**
- Modify: `web/vercel.json`
- Remove: `web/CNAME`, `.github/workflows/deploy-pages.yml`
- Create: `.github/workflows/deploy-vercel.yml`

- [ ] **Step 1: Update `web/vercel.json` and remove Pages config**

Update `web/vercel.json` to use safe `index.html#download` fallback:
```json
{
  "buildCommand": "sed -i 's|TESTFLIGHT_URL|'\"${TESTFLIGHT_URL:-index.html#download}\"'|g' index.html privacy.html support.html",
  "cleanUrls": true
}
```
Remove `web/CNAME` and `.github/workflows/deploy-pages.yml`.

- [ ] **Step 2: Create `.github/workflows/deploy-vercel.yml`**

Create GitHub Actions workflow for deploying `web/` to Vercel using `amondnet/vercel-action@v25` or official Vercel CLI (`vercel build` & `vercel deploy --prebuilt`).

- [ ] **Step 3: Commit**

```bash
git rm web/CNAME .github/workflows/deploy-pages.yml 2>/dev/null || true
git add web/vercel.json .github/workflows/deploy-vercel.yml
git commit -m "ci: configure GitHub Actions Vercel deployment workflow and clean up Pages deployment configs"
```
