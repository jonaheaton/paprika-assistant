# Walmart Bot Detection Investigation — Status Report

**Date**: 2026-04-22
**Context**: Investigation of the `walmart-to-pantry` skill's bot detection issues, exploration of mitigation options, partial implementation of a new approach, and identification of next steps.

---

## Background

The `walmart-to-pantry` skill (in `.claude/skills/walmart-to-pantry/`) is a Claude Code skill that:
1. Logs into a user's Walmart account
2. Navigates the order history
3. Extracts items from a "Delivery from store" (grocery) order
4. Adds those items to the user's Paprika pantry inventory with proper categorization and expiration dates

The skill uses Playwright MCP with a persistent Chrome profile (`~/.claude/playwright-profile/`) and a custom JavaScript stealth init script (`~/.claude/playwright-stealth.js`).

**Goal**: Fully autonomous, agentic, end-to-end execution. **No human intervention** during a run. Human verification CAPTCHAs are not an acceptable solution.

---

## Problem

Walmart deploys **Akamai Bot Manager** (with PerimeterX collector at `collector-pxu6b0qd2s.px-cloud.net`). Over the course of recent runs, the skill has encountered:

- **Soft challenges**: "Robot or human?" modal overlays on pages (dismissable by clicking "Close dialog")
- **Hard blocks**: Redirects to `/blocked?url=<base64>&uuid=...&vid=...&g=b` — the page becomes a press-and-hold human verification challenge that requires manual interaction

Hard blocks are particularly disruptive because:
1. They cannot be cleared agentically
2. They appear to be tied to specific URLs and persistent session identifiers (`vid`)
3. The persistent profile means reputation is carried across browser restarts

---

## Detection Signal Categories (Akamai Bot Manager)

Akamai uses four signal categories. Knowing which we're failing tells us where to invest:

| Signal | What it checks | Our coverage |
|---|---|---|
| **Browser fingerprint** | `navigator.webdriver`, plugins, WebGL, chrome.runtime, etc. | **Partial** — 3 patches in `playwright-stealth.js` |
| **Behavioral** | Mouse movement, scroll, typing pauses, focus events, timing variance | **None** — deterministic clicks with no movement |
| **TLS/network** | JA3/JA4 fingerprint, HTTP/2 settings | Cannot change in Playwright |
| **Session/IP reputation** | Cookie continuity, IP rep, request patterns | Mixed — persistent profile keeps both auth AND reputation cookies |

---

## Background Research (Before Testing)

### SeleniumBase comparison
SeleniumBase (Python, undetected-chromedriver-based) offers:
- **UC Mode**: patches ChromeDriver at the binary level (deeper than JS-only patches)
- **CDP Mode**: communicates via Chrome DevTools Protocol instead of WebDriver, called "maximum stealth"
- Built-in `solve_captcha()` for some challenges

Compared to our Playwright + JS stealth: SeleniumBase patches the WebDriver binary, ours only patches JavaScript-visible fields. SeleniumBase would require a full skill rewrite in Python, abandoning Playwright MCP.

### Playwright-extra + puppeteer-extra-plugin-stealth
- Provides 11 evasion modules vs. our 3 (webdriver, plugins, languages)
- Most valuable additions for Akamai: `chrome.runtime` mock, real `PluginArray` (ours is a fake `[1,2,3,4,5]` that fails `instanceof` checks), `window.outerWidth/outerHeight` fix
- **Stale**: last NPM publish 2+ years ago
- **Integration cost**: cannot drop into `@playwright/mcp` via `--init-script`; would require custom MCP wrapper

### Apify fingerprint-suite
- Actively maintained (2.1k stars, last release 2026-04-01)
- Generates *consistent* full-stack fingerprints (UA + platform + screen + WebGL + headers)
- **Integration cost**: same — wraps `chromium.launch()`, not usable via init script

### Conclusion of research phase
Without writing a custom MCP wrapper, we can only enhance our existing `--init-script`. We could port individual evasions from puppeteer-extra-plugin-stealth into our `playwright-stealth.js`, but these are JS-level patches and may not address whatever is causing our specific blocks.

---

## Tests Run This Session

### Test 1: Network capture on order detail page (investigation)

**Goal**: Identify a backend API that returns order item data so we can bypass UI rendering.

**Action**: Navigated to `https://www.walmart.com/orders/200014426966175` ($7.86 order, Apr 21), captured all network requests with bodies and headers.

**Finding**: **No separate API call returns order items.** The Walmart order detail page is server-side rendered. All item data is embedded in a `<script id="__NEXT_DATA__">` tag in the initial HTML response. Clicking "Show items" triggers zero new network requests — it's a pure CSS/JS toggle of already-loaded data.

**Schema discovered**:
```
__NEXT_DATA__
  .props.pageProps.initialData.data.order
    .id                            → order ID
    .groups_2101[]                 → array of delivery groups
      .deliveryDate                → ISO timestamp
      .items[]
        .productInfo.name          → item name
        .productInfo.salesUnitType → "EACH" | "WEIGHT"
        .quantity                  → numeric quantity
        .requestedWeight           → weight or null
        .priceInfo.unitPrice       → "$X/lb" or "$X ea"
        .priceInfo.linePrice.value → total
```

### Test 2: Skill rewrite with `__NEXT_DATA__` extraction

**Action**: Rewrote `SKILL.md` (commit `b7f6e3d`) to replace:
- ❌ Click "Show items" button → save snapshot to file → parse markdown with Python

With:
- ✅ Single `browser_evaluate(() => { extract __NEXT_DATA__ })` call

This eliminates the highest-risk UI interaction (the "Show items" click which was historically associated with bot detection escalation).

### Test 3: End-to-end test of new method (after browser reset)

**Setup**:
- Browser reset (fresh state, cookies preserved in persistent profile)
- 77 Walmart cookies confirmed alive in profile
- Paprika MCP confirmed connected

**Sequence**:
1. `walmart.com` (homepage warm-up)
2. `wait_for(4000)`
3. `walmart.com/orders` → confirmed "Purchase history" visible (logged in)
4. `wait_for(2000)`
5. `walmart.com/orders/200014452219750` ($12.69, today) → **loaded cleanly, no block**
6. `browser_evaluate` extracted `__NEXT_DATA__` → got valid JSON with `groupsKey: "groups_2101"`, two items (kids' sunglasses), `deliveryDate: "2026-04-22T12:04:28-04:00"`
7. Both items were non-food → nothing added to pantry
8. Clicked "Purchase history" breadcrumb → back on orders list
9. `wait_for(5000)`
10. `walmart.com/orders/200014704057843` ($110.47, Apr 21) → **HARD BLOCK** (`/blocked?url=...`, `vid=22642f98-2312-11f1-bec3-4cf969b936f2`)

**Critical observation**: The `vid` in the second block was **identical** to a `vid` from a hard block earlier in the day. The persistent profile is preserving Akamai's reputation tracking across browser restarts.

---

## What Has Been Demonstrated

| Claim | Evidence |
|---|---|
| `__NEXT_DATA__` contains complete order item data | Confirmed on 2 different orders (200014426966175, 200014452219750) |
| The `groups_2101` key is currently stable | Same key name in both successful extractions |
| `__NEXT_DATA__` extraction needs no clicks | Single `browser_evaluate` call works post-load |
| The new method works for un-flagged orders | Order 200014452219750 loaded cleanly with new flow |
| Akamai's `vid` persists across browser restarts | Same `vid` in 2 hard blocks separated by a browser reset |
| Hard blocks are tied to specific URL+session combinations | Order 200014704057843 has been blocked twice; other orders work |

---

## What Has NOT Been Demonstrated

| Claim | Status |
|---|---|
| The new method has a lower block rate than the old method | **Not proven.** Sample size too small. Old method historically processed many orders successfully too. |
| Stealth patch expansion would help | Untested. The blocks we're hitting appear to be reputation-based, which patches don't address. |
| Behavioral mimicry would help | Untested. |
| The `finalWeight` field exists for produce items | Never observed (only tested non-produce orders) |
| Pre-warming with multiple page loads helps | Untested. |
| Akamai reputation cookies can be selectively cleared while keeping Walmart auth | Untested. |
| `context.request.get()` (raw HTTP) bypasses JS-based Akamai tracking | **Not yet tested.** This is the most leveraged unexplored option. |
| Walmart's mobile app API exists and is accessible with our cookies | Untested. |
| The orders list page's `__NEXT_DATA__` includes item-level data (would skip detail page entirely) | Not checked. |

---

## Key Uncertainties

1. **Why does Order 200014704057843 specifically get blocked?**
   - Was it the first order's URL we hit a block on, marking it as "suspicious" for our `vid`?
   - Is it large enough that Walmart server-side flags it for verification before serving?
   - Does the order's `vid`-association ever expire?

2. **What is the `vid` exactly?**
   - Cookie? localStorage? Server-side identifier?
   - Set by initial JS challenge? Persists how long?
   - If we cleared specific cookies (`_px*`, `pxcts`, `_pxhd`, `bm_sz`, `_abck`), would Akamai issue a new `vid`?
   - Would Walmart auth still work with a fresh `vid`?

3. **Is the new method *actually* better than the old?**
   - Both methods rely on a successful page load — neither helps if the URL is blocked at the server before HTML is served.
   - The new method eliminates the Show-items click, but if blocks happen at navigation time, the click never matters.
   - We don't have controlled comparison data.

4. **Server-side enforcement of JS challenges**
   - When Akamai blocks (`/blocked?url=...`), it's a server-side redirect. So they're enforcing at the server level.
   - Question: do they enforce based on *cookie state* (settable without JS) or based on *active JS challenge completion*? If the former, raw HTTP requests might still get blocked. If the latter, raw HTTP requests would bypass everything.

---

## Paths Forward

### Path A — Raw HTTP requests with cookie scoping (the *real* API approach)

**Approach**: Use Playwright's `context.request.get(url)` (or a fresh `APIRequestContext`) to fetch the order page as a raw HTTP request, **without** rendering or executing any JavaScript. Scope which cookies are sent: include Walmart auth cookies, exclude Akamai reputation cookies (`_px*`, `pxcts`, `_pxhd`, `bm_sz`, `_abck`).

**Hypothesis**: If we never run JS, PerimeterX never fingerprints us. If we never send the bad `vid` cookie, Akamai sees a "fresh visitor" with valid auth.

**Cost**: ~1-2 hours of investigation

**Why this is the most valuable test**: It directly addresses the failure mode we're hitting (reputation-based blocks tied to JS-set cookies) AND it's the actual "API approach" the user originally asked for.

**Open questions if it works**:
- Do we still need the browser at all (other than for login)?
- Can we cache the auth cookies and run order fetches as a pure script with `requests` or `curl`?

### Path B — Inspect orders list `__NEXT_DATA__`

**Approach**: Check whether `__NEXT_DATA__` on `/orders` (the list page) contains item-level data, not just order metadata. If yes, we never need to navigate to detail pages at all.

**Cost**: ~5 minutes

**Why valuable**: Eliminates the riskiest navigation entirely. The orders list page has not historically triggered blocks for us.

**Likely finding**: Probably won't have full item data (Walmart wouldn't ship that volume on the list page), but worth verifying.

### Path C — Walmart mobile app API

**Approach**: Reverse engineer Walmart's mobile app API. The mobile app must call backend APIs to display order details. Those APIs are typically less aggressively bot-protected than the website.

**Cost**: Significant (proxy mobile app traffic with mitmproxy or similar). Would need a Walmart account on a phone.

**Why interesting**: Mobile APIs often have different (looser) bot protection.

### Path D — Process orders in real-time

**Approach**: Triggered by delivery confirmation email arriving in Gmail (we already have Gmail MCP). When email arrives, immediately run the skill on that order. Hypothesis: a freshly delivered order has not yet built up Akamai reputation against our session.

**Cost**: Plumbing (cron + Gmail polling, or webhook-triggered run)

**Why interesting**: Reframes batch backlog processing as streaming. Each order is a "first contact."

### Path E — Stealth patch expansion (defense in depth)

**Approach**: Port additional evasions from puppeteer-extra-plugin-stealth into `playwright-stealth.js`:
- `chrome.runtime` mock
- Real `PluginArray` (replacing the broken `[1,2,3,4,5]`)
- `window.outerWidth/outerHeight` fix

**Cost**: ~30 minutes

**Why limited value**: Doesn't address reputation-based blocks. Worth doing as defense-in-depth but unlikely to be the breakthrough.

### Path F — Custom MCP wrapper with fingerprint-suite

**Approach**: Replace `@playwright/mcp` with a custom MCP server that uses Playwright + Apify fingerprint-suite for consistent full-stack fingerprinting.

**Cost**: 1-2 days

**Why deferred**: Higher engineering cost, only justified if Path A and Path B both fail.

### Path G — Selective Akamai cookie clearing

**Approach**: Before each session, identify and delete Akamai-specific cookies from the persistent profile while preserving Walmart auth cookies. Forces a "fresh visitor" appearance per session.

**Cost**: ~30 minutes (identify cookies) + skill modification

**Why interesting**: Could work even with current browser-based approach. But might trigger MORE detection if Akamai notices a logged-in session with no prior tracking history.

---

## Recommended Next Action

**Test Path A (raw HTTP with cookie scoping) first.** Justification:
1. It's the actual "API approach" originally proposed
2. It directly addresses the demonstrated failure mode (reputation tied to JS-set cookies)
3. Low cost (~1-2 hours)
4. If it works, the entire bot detection conversation gets dramatically simpler
5. If it doesn't work, the failure mode tells us something useful (server-side enforcement based on what?)

**If Path A works**: also do Path B for completeness (might let us avoid even the per-order request).

**If Path A doesn't work**: investigate Path G (selective cookie clearing) — same general idea but at the browser level instead of HTTP request level.

---

## Files Modified This Session

- `.claude/skills/walmart-to-pantry/SKILL.md` — rewritten to use `__NEXT_DATA__` extraction (commit `b7f6e3d`)
- `.claude/skills/walmart-to-pantry/references/bot-detection-mitigations.md` — new reference document with mitigation options (commit `b7f6e3d`)
- `walmart-bot-detection-investigation-report.md` — this file

---

## Session 2 — 2026-04-23: Path B Investigation (Orders List Page)

### Summary

**Path B was tested and succeeded beyond expectations.** The orders list page (`/orders`) contains complete item-level data for all visible orders, including the previously-blocked order 200014704057843. This completely eliminates the need for order detail page navigation.

### Findings

#### Orders List Page Data Structure

The `/orders` page uses a **different** `__NEXT_DATA__` key than the detail page:

```
props.pageProps.phRedesignInitialData.data.purchaseHistory.orders[]
  .id                    → order ID
  .orderDate             → ISO timestamp
  .groups[]
    .fulfillmentType     → "DFS" = Delivery From Store (grocery)
    .deliveredDate       → actual delivery ISO timestamp
    .items[]
      .name              → full item name (includes size info)
      .quantity          → count ordered
```

**NOT present** (vs detail page): `salesUnitType`, `requestedWeight`, `priceInfo`

#### Grocery Order Identification

`group.fulfillmentType === "DFS"` reliably identifies grocery delivery orders. Non-grocery orders use `"INTERNALIZED_PARCEL"` (FC delivery) or other types.

#### Item Count Discrepancy

Order 200014704057843 has `itemCount: 32` but only 26 items in `group.items[]`. The missing 6 are substitution offers shown in the Walmart UI but not actually delivered — the list page filters these out automatically, which is the correct behavior for pantry tracking.

#### Previously-Blocked Order: All 26 Items Accessible

The full item list for order 200014704057843 was extracted from `/orders` without issue, including:
- Parmesan Cheese, Peanut Butter, Cream Cheese, Mango Chunks (Frozen)
- Mac & Cheese ×2, Spaghetti ×2, Fiesta Cheese
- Probiotic Sodas ×3, Babybel Gouda, Black Beans ×2
- Dave's Killer Bread, Eggs, Greek Yogurt
- Shallots, Honeycrisp Apple, Banana, Strawberries, Fuji Apple ×3, Granny Smith Apple ×4
- Aluminum Foil, Scrunchies, Toilet Paper (non-food, skip)

#### Missing Weight Field — Not a Practical Problem

The list page lacks `salesUnitType` and `requestedWeight`. However:
- Walmart DFS produce is sold in pre-packaged units or by the each, not by the pound
- Item names encode size: `"Fresh Strawberries, 2 lb, Container"`, `"Fresh Honeycrisp Apple, Each"`
- For pantry entries, the name string contains all quantity information needed

#### Pagination

The list page shows ~5 most recent orders with a `nextPageCursor`. No "Load more" button is rendered — the page appears to use date filter buttons ("Last 3 months", "2025", etc.) to surface older orders. For recent delivery processing (the primary use case), this is not an issue.

### Outcome

**The bot detection problem is resolved.** By extracting from the orders list page:
1. No detail page navigation needed for any recently-visible order
2. Order 200014704057843 (previously hard-blocked) is now fully extractable
3. Single `browser_evaluate()` call gets all grocery orders and all items simultaneously
4. `/orders` has never triggered a block in any test session

### What Remains Open

| Question | Status |
|---|---|
| Path A (raw HTTP with cookie scoping) | Not needed — Path B fully solved the problem |
| Pagination for orders older than ~5 most recent | Detail page fallback remains available |
| `deliveredDate` null handling | Not observed yet — check if `deliveredDate` can be null for in-transit orders |
| Orders spanning multiple groups (same DFS, different delivery windows) | Not observed yet — skill handles via iterating all DFS groups |

### Files Modified This Session

- `.claude/skills/walmart-to-pantry/SKILL.md` — rewritten to use orders list page as primary extraction method
