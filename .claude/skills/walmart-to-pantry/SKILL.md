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

## How Item Data Is Extracted

Walmart server-renders all order item data into a `<script id="__NEXT_DATA__">` tag on page load. **No "Show items" click, no snapshot, no file parsing needed.** A single `browser_evaluate()` call extracts structured JSON immediately after the page loads.

Data path: `__NEXT_DATA__.props.pageProps.initialData.data.order.groups_2101[]`

Each group contains:
- `deliveryDate` — ISO timestamp of delivery
- `items[]` — received items with `quantity`, `productInfo.name`, `requestedWeight`, `salesUnitType`, `priceInfo`

## Workflow

### 1. Navigate to Walmart Orders

```javascript
mcp__plugin_playwright_playwright__browser_navigate(url: "https://www.walmart.com")
// 3-5s warm-up pause — cold-start directly to /orders is a bot signal
mcp__plugin_playwright_playwright__browser_wait_for(time: 4000)
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

Get the order ID from the return link URL (e.g., `/orders/200014426966175/returns` → order ID `200014426966175`).

### 4. Handle Bot Detection on the Orders List (if it appears)

Walmart's Akamai bot detection occasionally appears on the orders list as a **modal overlay**. Waiting does not resolve it — click "Close dialog", then wait before continuing.

```javascript
mcp__plugin_playwright_playwright__browser_snapshot()
// If snapshot shows dialog "Robot or human?" with a "Close dialog" button:
mcp__plugin_playwright_playwright__browser_click(ref: <close-dialog-button-ref>)
mcp__plugin_playwright_playwright__browser_wait_for(time: 4000)
mcp__plugin_playwright_playwright__browser_snapshot()
```

### 5. Extract Order Items via __NEXT_DATA__

Navigate to the order detail page. After it loads, extract all data in a single JavaScript call — no clicking required.

```javascript
mcp__plugin_playwright_playwright__browser_navigate(url: "https://www.walmart.com/orders/<ORDER_ID>")
// If bot detection appears (/blocked?url=... or "Robot or human?" modal), see Common Issues below
mcp__plugin_playwright_playwright__browser_wait_for(time: 2000)
```

Then extract the data:

```javascript
mcp__plugin_playwright_playwright__browser_evaluate(function: `() => {
  const order = JSON.parse(document.getElementById('__NEXT_DATA__').textContent)
    .props.pageProps.initialData.data.order;

  return JSON.stringify({
    orderId: order.id,
    groups: order.groups_2101.map(group => ({
      deliveryDate: group.deliveryDate,
      items: group.items.map(item => ({
        name: item.productInfo.name,
        quantity: item.quantity,
        salesUnitType: item.productInfo.salesUnitType,
        requestedWeight: item.requestedWeight,
        unitPrice: item.priceInfo?.unitPrice?.displayValue,
        linePrice: item.priceInfo?.linePrice?.value
      }))
    }))
  }, null, 2);
}`)
```

**Produce items (weight-based):** Items ordered by weight have `salesUnitType: "WEIGHT"` and a non-null `requestedWeight`. Use the weight value as the quantity (e.g., `"1.2 lbs"`). If a `finalWeight` field is present (to be confirmed on first produce order), prefer that over `requestedWeight` — it reflects what was actually delivered.

**Multiple groups:** Some orders have multiple delivery groups (e.g., same-day + next-day). Process each group's `deliveryDate` and `items` independently.

**Substitution items:** In the JSON response, `items[]` contains only received items. Substitution offer rows (visible in the UI but not actually delivered) do not appear here — no filtering needed.

### 6. Categorize and Add to Pantry

For each food item:
1. **Determine aisle**: Map to Paprika aisle name (see references/mappings.md)
2. **Calculate expiration**: From `deliveryDate` in the group (see references/mappings.md)
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

**Multiple quantities:** If `quantity > 1` with a unit size in the name (e.g., qty 2 of 15 oz cans), combine into one entry (e.g., `"30 oz (2 cans)"`).

**Weight items:** Use the weight as the quantity string (e.g., `"1.2 lbs"`).

### 7. Return to Orders List

After finishing an order, click the "Purchase history" breadcrumb rather than navigating directly to `/orders` — a bare URL load right after processing is a bot signal.

```javascript
// The breadcrumb is always present: My account / Purchase history / Order details
mcp__plugin_playwright_playwright__browser_click(ref: <purchase-history-breadcrumb-ref>)
// Wait before processing next order — rapid sequential order loads trigger hard blocks
mcp__plugin_playwright_playwright__browser_wait_for(time: 5000)
```

**Between orders:** Wait 5+ seconds before navigating to the next order detail page. Never process two orders back-to-back without a pause.

## Common Issues

| Issue | Solution |
|-------|----------|
| Paprika tools not in deferred list | Run `/mcp` in Claude Code to reconnect claude.ai integration |
| Not logged in | Follow login flow; ensure persistent session is configured (see CLAUDE.md) |
| Hard block (`/blocked?url=...`) on order detail load | Stop. Navigate back to homepage. Wait 5+ minutes before retrying. Caused by rapid sequential order loads. |
| Bot detection modal on orders list | Click "Close dialog", wait 4s, take fresh snapshot before continuing |
| `__NEXT_DATA__` missing or empty | Page may not have fully loaded — wait 2s and re-evaluate; if still missing, fall back to snapshot approach |
| `groups_2101` key missing | Walmart may rename this key in a future deploy — check `Object.keys(order)` for a key matching `groups_*` |
| Produce weight field unclear | Use `requestedWeight` if present; `finalWeight` may also exist (verify on first produce order) |
| Session expired after 60 days | Re-run login flow with `--headed` flag (see CLAUDE.md → Playwright Setup) |
| `params` validation error | Ensure params is JSON object, not string |

## References

- **references/mappings.md**: Complete aisle mappings and expiration heuristics
- **references/bot-detection-mitigations.md**: Options for reducing bot detection if blocks become frequent
