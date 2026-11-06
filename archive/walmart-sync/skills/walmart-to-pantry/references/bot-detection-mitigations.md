# Walmart Bot Detection — Mitigation Options

Reference document for improving the walmart-to-pantry skill's resilience against Walmart's Akamai Bot Manager. Captures options to consider if/when we hit blocks again.

**Context**: Walmart uses Akamai Bot Manager. We've experienced soft challenges (modal dialog) and hard blocks (`/blocked?url=...`). The order detail page is the most aggressive surface — the orders list is comparatively safe.

---

## Detection Signal Categories

Akamai uses four signal types. Knowing which we're failing tells us where to invest:

| Signal | What it checks | Our coverage |
|---|---|---|
| **Browser fingerprint** | `navigator.webdriver`, plugins, WebGL, chrome.runtime, etc. | Partial — 3 patches in `playwright-stealth.js` |
| **Behavioral** | Mouse movement, scroll, typing pauses, focus events, timing variance | **None** — deterministic clicks with no movement |
| **TLS/network** | JA3/JA4 fingerprint, HTTP/2 settings | Can't change in Playwright |
| **Session/IP reputation** | Cookie continuity, IP rep, request patterns | Good — persistent profile + residential IP |

**Working hypothesis**: Behavioral signals are what escalate us from soft modals to hard blocks. Even with perfect fingerprints, our snapshot → click → snapshot loop has zero mouse movement, deterministic timing, and instant page interaction. To Akamai this looks blatantly automated.

---

## Option Tier 1: Behavioral Mimicry (highest expected impact for UI path)

These add human-like signals to the existing flow. Cheap to implement, high payoff.

### Randomize delays
Replace fixed `browser_wait_for(time: 4000)` with jittered delays.
- Use `1500-3500ms` random for post-modal waits
- Use `800-2200ms` random between actions
- Even simple uniform random is better than deterministic 4000

### Mouse trajectory before clicks
Playwright supports `page.mouse.move(x, y, { steps: 8 })` for stepped trajectory. Real users never teleport the cursor to an element.
- Move mouse to element with 5-15 intermediate steps before clicking
- Bezier curves are even better than linear (libraries: `ghost-cursor`)
- Most important on the "View details" and "Show items" buttons

### Scroll behavior
- Scroll the page once after load, before clicking anything
- Humans scan the page; we click immediately
- Even a small scroll down + back up adds a strong human signal

### Read time
- Add 2-5s "read time" after page loads before any action
- Especially important after the orders list loads — humans pick which order to click

### Implementation note
The Playwright MCP doesn't expose `page.mouse.move` directly. Options:
- Use `browser_evaluate` to inject mouse movement via JS dispatched events
- Switch to a custom MCP wrapper that exposes more Playwright primitives
- Switch tooling (see Tier 4)

---

## Option Tier 2: Stealth Patch Expansion (cheap defense in depth)

Our `~/.claude/playwright-stealth.js` covers 3 fields. The full `puppeteer-extra-plugin-stealth` covers 11. Most valuable additions for Akamai:

### Highest priority
1. **`chrome.runtime` mock** — Akamai checks for `window.chrome` object existence. Headless Chrome lacks the runtime portion.
2. **Real `PluginArray`** — our current `[1,2,3,4,5]` fails `instanceof PluginArray` checks. Need actual `PluginArray` and `MimeTypeArray` instances.
3. **`window.outerWidth`/`outerHeight`** — these are `0` in headless mode. Hard tell.

### Lower priority (only if blocks persist after above)
4. `webgl.vendor` — patches WebGL renderer/vendor strings
5. `iframe.contentWindow` — fixes iframe-based detection without breaking reCAPTCHA
6. `media.codecs` — spoofs proprietary codec support
7. `navigator.vendor` — sets correct vendor string
8. User-agent override — make sure UA matches the rest of the fingerprint

**Source**: All patches are MIT-licensed in [puppeteer-extra-plugin-stealth/evasions/](https://github.com/berstend/puppeteer-extra/tree/master/packages/puppeteer-extra-plugin-stealth/evasions). Can be ported individually to our init script.

**Caveat**: The puppeteer-extra-plugin-stealth project hasn't published in 2+ years. Some patches may need updates for modern Chrome.

---

## Option Tier 3: Workflow Constraints (free, helps avoid escalation)

Process changes that reduce signal load per session.

### Session-level
- **Pre-warm**: Load `walmart.com` homepage first, scroll, wait 5-10s, *then* navigate to `/orders`. Cold-start to `/orders` is itself a signal.
- **One order per session** when blocks are recent. We currently process several in a row, which compounds the behavioral signature.
- **Cooldown after a hard block**: hours, not minutes. Current "10+ min" is probably too short — Akamai reputation persists.

### Per-order
- Already doing: breadcrumb navigation back instead of URL load (good — keep this)
- Already doing: dismiss modal then wait before next click (good — keep this)
- Add: vary the order of actions slightly so we don't have a perfectly predictable sequence

---

## Option Tier 4: Tooling Alternatives (rewrite cost, possibly higher ceiling)

If Tier 1-3 still hit walls, switch the underlying automation tool.

### Apify `fingerprint-suite`
- **Status**: Actively maintained (2.1k stars, releases as recent as 2026)
- **Approach**: Generates a *consistent* full-stack fingerprint (UA + platform + screen + WebGL + headers all coherent). Inconsistent patches are themselves a detection signal.
- **API**: `newInjectedContext(browser, opts)` wraps `chromium.launch()`
- **Cost**: Requires writing a custom MCP wrapper since `@playwright/mcp` doesn't accept fingerprint-suite as a plugin. Maybe 1-2 days of work.
- **When**: If we exhaust Tier 1-3 and still get blocked.

### `playwright-extra` + `puppeteer-extra-plugin-stealth`
- **Status**: Stale (last NPM publish 2+ years ago)
- **Approach**: Plugin framework over Playwright, includes the stealth bundle
- **Cost**: Same custom MCP wrapper requirement as fingerprint-suite
- **When**: Generally prefer fingerprint-suite — more recent, more comprehensive

### SeleniumBase (Python)
- **Status**: Actively maintained, very popular
- **Approach**: UC Mode patches ChromeDriver at the binary level (deeper than JS-only patches). CDP Mode for "maximum stealth". Built-in CAPTCHA solving.
- **Cost**: Full rewrite of the skill in Python. Loses Playwright MCP integration entirely.
- **When**: If both Playwright-ecosystem options fail and we're committed to keeping this automation working.

### Custom Playwright MCP wrapper
Independent of the above, we could write our own thin MCP server that:
- Uses Playwright directly (so we control launch options)
- Adds behavioral primitives (mouse trajectory, scroll, randomized delays)
- Optionally integrates fingerprint-suite or playwright-extra
- Exposes a Walmart-specific tool surface (e.g., `extract_order_items(order_id)`)

This is the highest-effort but highest-control option. Worth doing if Walmart automation becomes a long-term load-bearing feature.

---

## What We've Already Tried (don't re-investigate)

| Mitigation | Result |
|---|---|
| `--browser chrome` (real Chrome vs Chromium) | Helps — kept |
| `--user-data-dir` persistent profile | Helps — kept |
| JS patches: webdriver, plugins, languages | Some help — but plugins patch is incorrect (fake array, not PluginArray) |
| Modal dismiss + 4s wait | Helps for soft modals |
| Slow down after dismissal (2s between actions) | Helps avoid escalation |
| Breadcrumb nav vs URL load | Helps — kept |
| `--disable-features=AutomationControlled` (Playwright default) | Insufficient alone — needed JS patch too |

---

## Decision Heuristics

**If hitting soft modals only**: Stay on current approach + add Tier 1 (behavioral). Probably enough.

**If hitting hard blocks regularly**: Tier 1 + Tier 2 + Tier 3 together. Most likely scenario.

**If still blocked after Tier 1-3**: Tier 4 — start with fingerprint-suite + custom MCP wrapper.

**If everything fails**: API approach (see separate plan) is the escape hatch — bypasses the UI surface entirely.
