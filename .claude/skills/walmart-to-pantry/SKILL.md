---
name: walmart-to-pantry
description: Extract grocery items from Walmart orders and add them to Paprika pantry inventory. Use when the user wants to add items from a Walmart grocery order to their Paprika pantry, transfer Walmart purchases to pantry tracking, or sync Walmart order history with Paprika inventory.
---

# Walmart to Pantry

Automate transferring grocery items from Walmart orders into Paprika pantry inventory with proper categorization and expiration dates.

## Workflow

### 1. Access Walmart Order

Execute the Chrome shortcut to view the order details:

```javascript
// Get available Chrome shortcuts
mcp__claude-in-chrome__shortcuts_list(tabId)

// Execute the view-order-details shortcut
mcp__claude-in-chrome__shortcuts_execute(
  tabId: <tab_id>,
  shortcutId: <found_shortcut_id>,
  command: "view-order-details"
)

// Wait for execution to complete
wait 5 seconds

// Read the page content
mcp__claude-in-chrome__read_page(tabId, filter: "all")
```

### 2. Extract Grocery Items

Parse the order page for food items. Extract:
- Item name
- Quantity and unit (oz, lb, ea, etc.)
- Category hints from product names

Filter out non-food items (tissues, paper products, personal care, cleaning supplies).

### 3. Categorize and Add to Pantry

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

### 4. Batch Processing

Add multiple items in parallel for efficiency. Use parallel tool calls for independent pantry additions.

## Key Considerations

- **Aisle names must match exactly**: Use names from references/mappings.md
- **Expiration dates**: Only add for perishables; frozen items need no expiration
- **Quantities**: Preserve units from order (oz, lb, ea, count)
- **Non-food items**: Skip entirely, don't add to pantry
- **Multiple quantities**: Combine total quantity (e.g., "Qty 2" of 16 oz = "32 oz")

## References

- **references/mappings.md**: Complete aisle mappings and expiration heuristics
