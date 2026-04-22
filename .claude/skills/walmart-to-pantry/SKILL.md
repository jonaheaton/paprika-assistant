---
name: walmart-to-pantry
description: Extract grocery items from Walmart orders and add them to Paprika pantry inventory. Use when the user wants to add items from a Walmart grocery order to their Paprika pantry, transfer Walmart purchases to pantry tracking, or sync Walmart order history with Paprika inventory.
---

# Walmart to Pantry

Automate transferring grocery items from Walmart orders into Paprika pantry inventory with proper categorization and expiration dates.

## Prerequisites

**Browser:** Uses Playwright MCP (`mcp__plugin_playwright_playwright__*` tools). Claude-in-Chrome does not work reliably in headless/remote sessions due to macOS permission dialogs.

**Playwright session:** Must be configured with a persistent profile (see CLAUDE.md → Playwright Setup). Without it, the browser will require login every run.

**Paprika MCP:** Verify `mcp__claude_ai_Paprika__pantry` appears in the deferred tools list before starting. If it doesn't:
- Run `/mcp` in the Claude Code session to reconnect the claude.ai integration
- Ask the user to reconnect from the Claude Code MCP menu if `/mcp` doesn't work
- Once reconnected, use ToolSearch to load the schema before calling it

## Workflow

### 1. Navigate to Walmart Orders

```javascript
mcp__plugin_playwright_playwright__browser_navigate(url: "https://www.walmart.com/orders")
mcp__plugin_playwright_playwright__browser_snapshot()
```

**Authentication check:** If the page shows "Sign in or create account", the session has expired — follow the login flow below. If it shows "Purchase history" or "Hi, [name]", skip to step 3.

### 2. Login Flow (if not authenticated)

Walmart's login is two-step: email → password.

```javascript
// Click "Sign in or create account" button, then check for bot detection
mcp__plugin_playwright_playwright__browser_click(ref: <sign-in-button-ref>)
mcp__plugin_playwright_playwright__browser_snapshot()
// If "Robot or human?" appears as a full page during login, wait — it auto-resolves to the login form
// (This is different from the modal dialog that appears on the order details page — see Step 4)

// Fill email (ask user for their email)
mcp__plugin_playwright_playwright__browser_type(ref: <email-field-ref>, text: <email>)
mcp__plugin_playwright_playwright__browser_click(ref: <continue-button-ref>)
mcp__plugin_playwright_playwright__browser_snapshot()

// Password step: user must type password directly into the browser window
// "Keep me signed in" checkbox should be checked (default) — leave it checked
// Ask user to type password and click Sign In, then say "done"
```

After successful login, Walmart redirects to `/orders?action=SignIn` with "Purchase history" visible.

### 3. Find the Grocery Order to Process

The purchase history page lists all orders by date. Grocery orders are labeled **"Delivery from store"**. Non-grocery orders (marketplace sellers, electronics, etc.) say "Delivery" with a seller name.

**If only one "Delivery from store" order is visible:** use it.

**If multiple "Delivery from store" orders are visible on the same day:** prefer the one with the largest order total — the small one is typically a correction or partial redelivery. If it's unclear, ask the user which order to process.

Click the "View details" button for the chosen order.

```javascript
mcp__plugin_playwright_playwright__browser_click(ref: <view-details-button-ref>)
```

### 4. Handle Bot Detection (if it appears)

Walmart's Akamai bot detection can appear at two points:
- **Orders list page** (rare): modal appears before you've clicked anything
- **After clicking "View details"** (more common): modal appears as an overlay

The modal is a **modal overlay**, not a full-page replacement. Waiting does not resolve it — you must click "Close dialog". After dismissing, use `browser_wait_for` to insert an actual browser-level delay — **do not use bash `sleep`**, which only delays you, not the browser. Rapid browser interactions after dismissal escalate detection and trigger a hard block at `/blocked?url=...`.

```javascript
mcp__plugin_playwright_playwright__browser_snapshot()
// If snapshot shows dialog "Robot or human?" with a "Close dialog" button:
mcp__plugin_playwright_playwright__browser_click(ref: <close-dialog-button-ref>)
mcp__plugin_playwright_playwright__browser_wait_for(time: 4000)  // 4s actual browser delay
mcp__plugin_playwright_playwright__browser_snapshot()
// Confirm dialog is gone before continuing
```

**After a bot modal dismissal, slow down for the rest of the order** — use `browser_wait_for(time: 2000)` between every subsequent action on that page (snapshot, Show items click, etc.).

**Escalation pattern to avoid:** dismissing a bot modal → immediately clicking a stale ref (error) → snapshot shows another modal → dismissing again → navigation = hard block. Always take a fresh snapshot before clicking anything after a dismissal.

### 5. Extract All Order Items

On the order details page, items are collapsed by default. The page shows a thumbnail strip with a "Show items" button. **Dismiss any open dialogs first** — an open dialog overlay will block the click.

```javascript
mcp__plugin_playwright_playwright__browser_click(ref: <show-items-button-ref>)
// Save to file — snapshot will be large
mcp__plugin_playwright_playwright__browser_snapshot(filename: ".playwright-mcp/items-expanded.md")
```

**Note on item counts:** The "N items received" count shown on the page includes individual units from multipacks and substitution rows. The number of visible product lines will always be fewer — this is expected. Don't scroll looking for missing items once the full list is visible.

The item list has two sections:
- **Weight-adjusted**: produce sold by weight (e.g., apples, bananas). Each entry shows `Qty N` and `Final weight X lbs`.
- **Shopped**: all other items. Each entry shows `Qty N`.

**Substitution items:** Walmart sometimes inserts a "substitution offer" row alongside a received item. These rows have an "Add to cart" button but **no `Qty N` text**. Skip them — only items with an explicit Qty were actually received.

Parse the snapshot with Python:

```bash
python3 << 'EOF'
import re

with open('.playwright-mcp/items-expanded.md') as f:
    content = f.read()

# Items start at "Weight-adjusted" section (produce) or "Shopped" section (all others)
# Fall back to just before the first "Add to cart" button if neither header exists
start = content.find('Weight-adjusted')
if start == -1:
    start = content.find('Shopped')
if start == -1:
    start = content.find('Add to cart')
end = content.find('How can we help?')
items_section = content[start:end] if end != -1 else content[start:]

# Each item block ends at its "Add to cart" button
blocks = re.split(r'- button "Add to cart - ', items_section)

for block in blocks[1:]:
    name_match = re.match(r'(.+?)"', block)
    if not name_match:
        continue
    name = name_match.group(1)
    qty_match = re.search(r'Qty (\d+)', block)
    qty = int(qty_match.group(1)) if qty_match else None
    weight_match = re.search(r'Final weight ([\d.]+) (\w+)', block)
    weight = f"{weight_match.group(1)} {weight_match.group(2)}" if weight_match else None
    # Skip substitution items (no Qty text)
    if qty is None:
        continue
    print(f"{name} — Qty {qty}" + (f" ({weight})" if weight else ""))
EOF
```

### 6. Categorize and Add to Pantry

For each food item:
1. **Determine aisle**: Map to Paprika aisle name (see references/mappings.md)
2. **Calculate expiration**: From the delivery date shown in the order header (see references/mappings.md)
3. **Skip non-food items**: paper products, cleaning supplies, personal care (see references/mappings.md)
4. **Add to pantry** — make all calls in parallel for efficiency:

First load the tool schema: `ToolSearch(query="select:mcp__claude_ai_Paprika__pantry")`

```python
mcp__claude_ai_Paprika__pantry(
  action="add",
  params={
    "ingredient": "<item_name>",
    "quantity": "<quantity_with_unit>",
    "aisle_name": "<paprika_aisle_name>",
    "expiration_date": "<YYYY-MM-DD>"  # omit for frozen/shelf-stable
  }
)
```

**Important:** `params` must be passed as a native JSON object, not a JSON string.

**Multiple quantities:** If Qty > 1 with a unit size (e.g., Qty 2 of 15 oz cans), combine into one entry (e.g., `"30 oz (2 cans)"`).

### 7. Return to Orders List

After finishing an order, **do not navigate directly to `https://www.walmart.com/orders`** — a bare URL load right after a bot-detected session is a strong automation signal. Instead, click the "Purchase history" breadcrumb link that's already on the order details page:

```javascript
// The breadcrumb is always present: My account / Purchase history / Order details
mcp__plugin_playwright_playwright__browser_click(ref: <purchase-history-breadcrumb-ref>)
// Example: link "Purchase history" [ref=eXXX] with /url: /orders
```

This looks identical to a human clicking back to their order list.

## Common Issues

| Issue | Solution |
|-------|----------|
| Paprika tools not in deferred list | Run `/mcp` in Claude Code to reconnect claude.ai integration |
| Not logged in | Follow login flow; ensure persistent session is configured (see CLAUDE.md) |
| Bot detection dialog | Click the "Close dialog" button — don't just wait; then wait 3-5s before next action |
| Hard block (`/blocked?url=...`) | Stop. Wait 10+ min before retrying — caused by rapid modal dismissals |
| "Show items" click blocked | Check for and dismiss any open dialogs first |
| Session expired after 60 days | Re-run login flow with `--headed` flag (see CLAUDE.md → Playwright Setup) |
| Item count on page doesn't match product lines | Expected — Walmart counts individual units; don't chase the discrepancy |
| Extra item with no Qty text | It's a substitution offer, not a received item — skip it |
| `params` validation error | Ensure params is JSON object, not string |

## References

- **references/mappings.md**: Complete aisle mappings and expiration heuristics
