---
name: walmart-to-pantry
description: Extract grocery items from Walmart orders and add them to Paprika pantry inventory. Use when the user wants to add items from a Walmart grocery order to their Paprika pantry, transfer Walmart purchases to pantry tracking, or sync Walmart order history with Paprika inventory.
---

# Walmart to Pantry

Automate transferring grocery items from Walmart orders into Paprika pantry inventory with proper categorization and expiration dates.

## Workflow

Two approaches are available:
- **Option A (Fast)**: Use Chrome shortcut if available
- **Option B (Fallback)**: Full browser automation

### 1. Set Up Browser Session

```javascript
// Get Chrome context (creates tab group if needed)
mcp__claude-in-chrome__tabs_context_mcp(createIfEmpty: true)

// Create new tab for this session
mcp__claude-in-chrome__tabs_create_mcp()

// Present plan for user approval
mcp__claude-in-chrome__update_plan(
  domains: ["walmart.com"],
  approach: [
    "Check for Walmart order shortcut",
    "Navigate to Walmart.com orders page",
    "Locate most recent grocery order",
    "Extract all grocery items with quantities",
    "Add items to Paprika pantry with proper categorization"
  ]
)
```

### 2. Check for Chrome Shortcut (Option A)

```javascript
// List available shortcuts
mcp__claude-in-chrome__shortcuts_list(tabId: <tab_id>)

// Look for shortcuts matching: "walmart", "order", "view-order-details", or similar
// If found, execute it and skip to step 4
// If not found or similar shortcuts exist, warn the user
```

**Warning Messages:**

If shortcut not found:
```
⚠️  No Walmart order shortcut found. Available shortcuts: [list them]

I'll use the full automation workflow instead. If you have a shortcut for
accessing Walmart orders, you can use it directly and I'll skip navigation steps.
```

If similar shortcuts found:
```
⚠️  Found similar shortcuts: [list them]

Did you mean one of these? If so, let me know and I'll use it.
Otherwise, I'll proceed with full automation.
```

**If shortcut found and executed:**
- Execute the shortcut
- Wait 5 seconds for navigation
- Skip to step 4 (Extract Order Items)

### 3. Navigate to Walmart Order History (Option B - Full Automation)

**Use this if no shortcut available or shortcut failed.**

```javascript
// Navigate to Walmart
mcp__claude-in-chrome__navigate(
  tabId: <tab_id>,
  url: "https://www.walmart.com/orders"
)

// Wait for page load
mcp__claude-in-chrome__computer(
  tabId: <tab_id>,
  action: "wait",
  duration: 3
)

// Take screenshot to see current state
mcp__claude-in-chrome__computer(
  tabId: <tab_id>,
  action: "screenshot"
)
```

**Authentication Check:** If not logged in, pause and ask user to log in manually, then continue.

### 4. Find Most Recent Grocery Order (Option B continued)

```javascript
// Read page to find order elements
mcp__claude-in-chrome__read_page(
  tabId: <tab_id>,
  filter: "interactive"
)

// Find the most recent order link
mcp__claude-in-chrome__find(
  tabId: <tab_id>,
  query: "most recent order details link"
)

// Click on the order to view details
mcp__claude-in-chrome__computer(
  tabId: <tab_id>,
  action: "left_click",
  ref: <order_ref_from_find>
)

// Wait for order details to load
mcp__claude-in-chrome__computer(
  tabId: <tab_id>,
  action: "wait",
  duration: 2
)
```

### 5. Extract Order Items (Both Options Converge Here)

**At this point, you should be on the Walmart order details page (via shortcut OR full automation).**

```javascript
// Read the full order page
mcp__claude-in-chrome__read_page(
  tabId: <tab_id>,
  filter: "all"
)

// Or use get_page_text for cleaner extraction
mcp__claude-in-chrome__get_page_text(
  tabId: <tab_id>
)
```

### 6. Parse Grocery Items

Parse the order page for food items. Extract:
- Item name
- Quantity and unit (oz, lb, ea, etc.)
- Category hints from product names

Filter out non-food items (tissues, paper products, personal care, cleaning supplies).

### 7. Categorize and Add to Pantry

For each food item:

1. **Determine aisle**: Map item to Paprika aisle name (see references/mappings.md)
2. **Calculate expiration**: Use category-based heuristics for perishables (see references/mappings.md)
3. **Add to pantry**:

```javascript
mcp__claude_ai_Paprika_Recipes__pantry(
  action: "add",
  params: {
    ingredient: "<item_name>",
    quantity: "<quantity_with_unit>",
    aisle_name: "<paprika_aisle_name>",
    expiration_date: "<YYYY-MM-DD>" // Optional, for perishables only
  }
)
```

### 8. Batch Processing

Add multiple items in parallel for efficiency. Use parallel tool calls for independent pantry additions.

## Key Considerations

**Browser Automation:**
- **Authentication**: If user isn't logged in, pause and ask them to log in manually
- **Page loading**: Always wait 2-3 seconds after navigation and clicks
- **Screenshots**: Take screenshots to verify page state before extracting data
- **Error handling**: If order page structure differs, use find() to locate elements dynamically

**Data Processing:**
- **Aisle names must match exactly**: Use names from references/mappings.md
- **Expiration dates**: Only add for perishables; frozen items need no expiration
- **Quantities**: Preserve units from order (oz, lb, ea, count)
- **Non-food items**: Skip entirely, don't add to pantry
- **Multiple quantities**: Combine total quantity (e.g., "Qty 2" of 16 oz = "32 oz")

## Common Issues

| Issue | Solution |
|-------|----------|
| Shortcut not found | Warn user and fall back to full automation |
| Shortcut exists but fails | Try full automation as fallback |
| Not logged into Walmart | Ask user to log in manually, then continue |
| Order page layout changed | Use find() with natural language queries instead of fixed selectors |
| Items missing quantities | Default to "1 ea" if quantity not found |
| Duplicate items in pantry | Check if item already exists before adding |
| Rate limiting | Add 1-2 second delays between pantry additions |

## Creating a Chrome Shortcut (Optional)

To speed up future runs, you can create a Chrome shortcut/workflow:

1. In Claude Chrome extension, navigate to your Walmart order details page
2. Create a new shortcut with a name like "view-order-details" or "walmart-order"
3. The skill will automatically detect and use it on future runs
4. Benefits: Faster execution, fewer clicks, more reliable

## References

- **references/mappings.md**: Complete aisle mappings and expiration heuristics
