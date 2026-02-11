---
name: walmart-to-pantry
description: Extract grocery items from Walmart orders and add them to Paprika pantry inventory. Use when the user wants to add items from a Walmart grocery order to their Paprika pantry, transfer Walmart purchases to pantry tracking, or sync Walmart order history with Paprika inventory.
---

# Walmart to Pantry

Automate transferring grocery items from Walmart orders into Paprika pantry inventory with proper categorization and expiration dates.

## Workflow

### 1. Set Up Browser Session

Get Chrome context and create a plan for the user to approve:

```javascript
// Get Chrome context (creates tab group if needed)
mcp__claude-in-chrome__tabs_context_mcp(createIfEmpty: true)

// Create new tab for this session
mcp__claude-in-chrome__tabs_create_mcp()

// Present plan for user approval
mcp__claude-in-chrome__update_plan(
  domains: ["walmart.com"],
  approach: [
    "Navigate to Walmart.com",
    "Access your account orders page",
    "Locate most recent grocery order",
    "Extract all grocery items with quantities",
    "Add items to Paprika pantry with proper categorization"
  ]
)
```

### 2. Navigate to Walmart Order History

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

### 3. Find Most Recent Grocery Order

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

### 4. Extract Order Items

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

### 5. Parse Grocery Items

Parse the order page for food items. Extract:
- Item name
- Quantity and unit (oz, lb, ea, etc.)
- Category hints from product names

Filter out non-food items (tissues, paper products, personal care, cleaning supplies).

### 6. Categorize and Add to Pantry

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

### 7. Batch Processing

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
| Not logged into Walmart | Ask user to log in manually, then continue |
| Order page layout changed | Use find() with natural language queries instead of fixed selectors |
| Items missing quantities | Default to "1 ea" if quantity not found |
| Duplicate items in pantry | Check if item already exists before adding |
| Rate limiting | Add 1-2 second delays between pantry additions |

## References

- **references/mappings.md**: Complete aisle mappings and expiration heuristics
