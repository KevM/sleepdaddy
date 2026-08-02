# SleepDaddy Supply-Chain, Security & Quality Hardening Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Address supply-chain security, TestFlight fallback UX, stat block labeling, absolute Open Graph URLs, and branch history cleanliness for SleepDaddy website (`web/`).

**Architecture:** Standard GitHub Actions workflow (`.github/workflows/deploy-vercel.yml`) with full SHA pinning, environment token passing, clean static HTML/CSS/JS in `web/`, and squashed git history.

---

### Task 1: GitHub Actions Supply-Chain Hardening (`.github/workflows/deploy-vercel.yml`)

**Files:**
- Modify: `.github/workflows/deploy-vercel.yml`

- [ ] **Step 1: Declare `permissions` block, pin SHA actions & Vercel CLI version, pass token via `env`**

- Add top-level `permissions: { contents: read }`.
- Pin `actions/checkout` to `11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2`.
- Pin `actions/setup-node` to `39370e3970a6d050c080011e4d35e03d1d393416 # v4.1.0`.
- Pin `vercel` CLI install: `npm install -g vercel@39.3.0`.
- Remove `--token=${{ secrets.VERCEL_TOKEN }}` flags from command lines and pass `VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}` via step `env:` blocks.

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/deploy-vercel.yml
git commit -m "security(ci): pin action SHAs, set permissions, pin vercel CLI, and pass token via env"
```

---

### Task 2: TestFlight Link Resolution & Visibly Degraded Unset UX (`web/main.js`, `web/vercel.json`, `web/index.html`)

**Files:**
- Modify: `web/main.js`
- Modify: `web/vercel.json`
- Modify: `web/index.html`, `web/privacy.html`, `web/support.html`

- [ ] **Step 1: Clean up `web/main.js` & `web/vercel.json`**

- Remove dead `window.TESTFLIGHT_URL` code.
- If `TESTFLIGHT_URL` is unset or `#download`, update CTA buttons with class `.btn-testflight` to display `"Coming Soon to TestFlight"` with disabled/amber styling instead of silent circular link loops.

- [ ] **Step 2: Commit**

```bash
git add web/main.js web/vercel.json web/index.html web/privacy.html web/support.html
git commit -m "fix(web): degrade TestFlight CTA gracefully when URL is unset and remove dead window property"
```

---

### Task 3: Stat Block Source Labeling & CSS Rule (`web/timeline-simulator.js` & `web/index.css`)

**Files:**
- Modify: `web/timeline-simulator.js`
- Modify: `web/index.css`
- Modify: `web/index.html`

- [ ] **Step 1: Add `.stat-source-badge` CSS rule to `web/index.css`**

Add clean CSS utility `.stat-source-badge` for source attribution badges in stat card section.

- [ ] **Step 2: Badge the entire stats block in `updateStats()`**

In `web/timeline-simulator.js`, update `updateStats()` to toggle a clear source attribution banner/badge on the entire stats section (`#stat-source-attribution`) reading `"Primary Data Source: Apple Watch"` when "All Sources" is active.

- [ ] **Step 3: Commit**

```bash
git add web/timeline-simulator.js web/index.css web/index.html
git commit -m "fix(web): add clean CSS rule and badge entire stats block with primary data source attribution"
```

---

### Task 4: Absolute Open Graph URLs, Twitter Card & Canonical Tags (`web/index.html`, `web/privacy.html`, `web/support.html`)

**Files:**
- Modify: `web/index.html`
- Modify: `web/privacy.html`
- Modify: `web/support.html`

- [ ] **Step 1: Update Open Graph, Twitter & Canonical tags**

- Set `<meta property="og:image" content="https://sleepdaddy.app/app-icon-180x180.png">` across all HTML files.
- Set `<meta name="twitter:card" content="summary">` (since icon is a 180x180 square).
- Ensure `<link rel="canonical" href="https://sleepdaddy.app/">` on `index.html`, `https://sleepdaddy.app/privacy` on `privacy.html`, `https://sleepdaddy.app/support` on `support.html`.

- [ ] **Step 2: Commit**

```bash
git add web/index.html web/privacy.html web/support.html
git commit -m "fix(web): use absolute og:image URLs, set twitter:card to summary, and add canonical links"
```

---

### Task 5: Git Branch History Cleanup (Remove 1.27 MB Blob from History)

**Files:**
- Git repository history on `website-dev` branch

- [ ] **Step 1: Interactive rebase / soft reset on `website-dev` to base commit `2b4d8b9` (or `af9eccf`)**

Reorganize commits so `web/app-icon.png` is never committed into git history, keeping history lean and fast (< 100 KB total).

- [ ] **Step 2: Force push clean branch to origin**

`git push --force-with-lease origin website-dev`
