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

**Primary method (orders list page):** Walmart server-renders all order data — including full item lists — into `<script id="__NEXT_DATA__">` on the `/orders` list page itself. A single `browser_evaluate()` call extracts every grocery order's items without navigating to individual order detail pages.

Data path: `__NEXT_DATA__.props.pageProps.phRedesignInitialData.data.purchaseHistory.orders[]`

Each order has `groups[]`. Grocery orders have `group.fulfillmentType === "DFS"` (Delivery From Store). Each group contains:
- `deliveredDate` — ISO timestamp of actual delivery
- `items[]` — delivered items with `name` and `quantity` (already filtered to delivered items only)

**Fallback method (order detail page):** Only use when an order is not on the current list page (older orders). See the Fallback section below.

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

// Fill email (ask user for their email)
mcp__plugin_playwright_playwright__browser_type(ref: <email-field-ref>, text: <email>)
mcp__plugin_playwright_playwright__browser_click(ref: <continue-button-ref>)
mcp__plugin_playwright_playwright__browser_snapshot()

// Password step: user must type password directly into the browser window
// "Keep me signed in" checkbox should be checked (default) — leave it checked
// Ask user to type password and click Sign In, then say "done"
```

After successful login, Walmart redirects to `/orders?action=SignIn` with "Purchase history" visible.

### 3. Extract All Grocery Orders from the List Page

Extract all recent grocery orders in a single call — no clicking, no detail page navigation:

```javascript
mcp__plugin_playwright_playwright__browser_evaluate(function: `() => {
  const data = JSON.parse(document.getElementById('__NEXT_DATA__').textContent);
  const orders = data?.props?.pageProps?.phRedesignInitialData?.data?.purchaseHistory?.orders || [];

  const groceryOrders = orders
    .filter(o => o.groups.some(g => g.fulfillmentType === 'DFS'))
    .map(o => ({
      orderId: o.id,
      orderDate: o.orderDate,
      groups: o.groups
        .filter(g => g.fulfillmentType === 'DFS')
        .map(g => ({
          deliveredDate: g.deliveredDate,
          items: g.items.map(item => ({
            name: item.name,
            quantity: item.quantity
          }))
        }))
    }));

  return JSON.stringify(groceryOrders, null, 2);
}`)
```

**Identifying grocery orders:** `fulfillmentType: "DFS"` = Delivery From Store (grocery). Non-grocery orders (marketplace parcels, FC_DELIVERY) have `fulfillmentType: "INTERNALIZED_PARCEL"` or similar and should be ignored.

**Which order to process:** If only one DFS order is recent, use it. If multiple DFS orders exist from the same day, prefer the largest (by `itemCount`) — small ones are typically corrections or partial deliveries. If unclear, ask the user.

**Items already filtered:** The `items[]` array contains only delivered items. Substitution offers (visible in the Walmart UI but not delivered) are excluded automatically.

### 4. Handle Bot Detection on the Orders List (if it appears)

Walmart's Akamai bot detection occasionally shows a **modal overlay** on the orders list. Waiting does not resolve it — click "Close dialog", then wait before re-evaluating.

```javascript
mcp__plugin_playwright_playwright__browser_snapshot()
// If snapshot shows dialog "Robot or human?" with a "Close dialog" button:
mcp__plugin_playwright_playwright__browser_click(ref: <close-dialog-button-ref>)
mcp__plugin_playwright_playwright__browser_wait_for(time: 4000)
// Re-run the browser_evaluate extraction after dismissing
```

### 5. Categorize and Add to Pantry

For each food item in the selected DFS order:
1. **Determine aisle**: Map to Paprika aisle name (see references/mappings.md)
2. **Calculate expiration**: From `deliveredDate` in the group (see references/mappings.md)
3. **Skip non-food items**: paper products, cleaning supplies, personal care (see references/mappings.md)
4. **Parse quantity from item name**: The `quantity` field is a count; the item name encodes the size. Examples:
   - `"Great Value Black Beans, 15 oz"` qty 2 → `"30 oz (2 cans)"`
   - `"Fresh Strawberries, 2 lb, Container"` qty 1 → `"2 lb"`
   - `"Fresh Fuji Apple, Each"` qty 3 → `"3"`
   - `"Dave's Killer Bread 21 Whole Grains, 27 ounce"` qty 1 → `"27 oz"`
5. **Add to pantry** — make all calls in parallel for efficiency:

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

## Fallback: Older Orders via Detail Page

If an order is not on the current list page (e.g., an order from weeks ago), navigate to its detail page to extract item data. This method carries bot detection risk — use only when the order is unavailable from the list page.

```javascript
mcp__plugin_playwright_playwright__browser_navigate(url: "https://www.walmart.com/orders/<ORDER_ID>")
// If bot detection appears (/blocked?url=... or "Robot or human?" modal), see Common Issues below
mcp__plugin_playwright_playwright__browser_wait_for(time: 2000)
```

Extract from the detail page (different schema than the list page):

```javascript
mcp__plugin_playwright_playwright__browser_evaluate(function: `() => {
  const order = JSON.parse(document.getElementById('__NEXT_DATA__').textContent)
    .props.pageProps.initialData.data.order;

  // Key name may change — check Object.keys(order) if groups_2101 is missing
  const groupsKey = Object.keys(order).find(k => k.startsWith('groups_'));

  return JSON.stringify({
    orderId: order.id,
    groups: order[groupsKey].map(group => ({
      deliveryDate: group.deliveryDate,
      items: group.items.map(item => ({
        name: item.productInfo.name,
        quantity: item.quantity,
        salesUnitType: item.productInfo.salesUnitType,
        requestedWeight: item.requestedWeight,
        unitPrice: item.priceInfo?.unitPrice?.displayValue
      }))
    }))
  }, null, 2);
}`)
```

**Produce items (weight-based):** Items with `salesUnitType: "WEIGHT"` have a `requestedWeight` field. Use that as the quantity string (e.g., `"1.2 lbs"`).

**After processing a detail page order:** Return to the orders list via the "Purchase history" breadcrumb (not direct URL navigation). Wait 5+ seconds before processing another.

## Common Issues

| Issue | Solution |
|-------|----------|
| Paprika tools not in deferred list | Run `/mcp` in Claude Code to reconnect claude.ai integration |
| Not logged in | Follow login flow; ensure persistent session is configured (see CLAUDE.md) |
| `phRedesignInitialData` missing or empty | Walmart may have restructured the page — check `Object.keys(data.props.pageProps)` for the new key containing orders |
| Bot detection modal on orders list | Click "Close dialog", wait 4s, re-run the browser_evaluate extraction |
| Hard block (`/blocked?url=...`) on detail page | Stop. Navigate to homepage. Wait 5+ minutes. This is why the list-page approach is preferred. |
| `__NEXT_DATA__` missing | Page not fully loaded — wait 2s and retry |
| `groups_2101` key missing on detail page | Check `Object.keys(order)` for a key starting with `groups_` |
| Session expired after 60 days | Re-run login flow with `--headed` flag (see CLAUDE.md → Playwright Setup) |
| `params` validation error | Ensure params is JSON object, not string |
| Order not on current list page | Use date filter buttons ("Last 3 months", etc.) or fall back to detail page approach |

## References

- **references/mappings.md**: Complete aisle mappings and expiration heuristics
- **references/bot-detection-mitigations.md**: Options for reducing bot detection if blocks become frequent
