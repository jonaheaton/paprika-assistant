# Pantry Cleanup Skill

**Trigger**: User wants to clean out old/spoiled items from their Paprika pantry

**Purpose**: Interactive workflow to identify and remove pantry items that have likely been consumed or gone bad, focusing on perishable sections.

---

## Workflow

### 1. Identify Target Sections

Focus on perishable aisles in priority order:
1. **Meat** - Most critical (fresh meat spoils quickly)
2. **Seafood** - Most critical
3. **Produce** - High priority
4. **Dairy** - High priority
5. **Bakery** - Moderate priority

### 2. Default Spoilage Heuristics

Use these age thresholds (days since purchase) to flag items:
- **Meat/Seafood**: >7 days (unless frozen section)
- **Produce**: >14 days
- **Dairy**: >30 days
- **Bakery**: >10 days
- **Frozen items**: >180 days (6 months)

### 3. Execution Steps

#### A. Query Each Perishable Aisle
```
pantry(action="query", params={
  "by_aisle": "<aisle_name>",
  "fields": ["aisle_name", "purchase_date"],
  "in_stock_only": false,
  "order_by": "purchase_date",
  "order_direction": "asc",
  "limit": 100
})
```

#### B. Calculate Item Age & Flag for Review
- Calculate days since purchase date
- Flag items exceeding threshold
- Identify duplicates (same ingredient name, flag older entries)

#### C. Present Batch for User Confirmation
Show items in a clear format:
```
Aisle: Produce
Items flagged for removal (>14 days old):

1. Arugula (ID: 315) - purchased 2026-01-03 (19 days ago)
2. Arugula (ID: 16) - purchased 2026-01-05 (17 days ago) [DUPLICATE]
3. avocado (ID: 362) - purchased 2025-10-12 (102 days ago)
4. green beans (ID: 505) - purchased 2020-08-03 (1634 days ago)
...

Remove these items? [Y/n]
```

#### D. Bulk Delete Confirmed Items
```
pantry(action="update", params={
  "item_ids": [315, 16, 362, 505, ...],
  "delete": true
})
```

### 4. Advanced Features

#### Duplicate Consolidation
When multiple entries exist for the same ingredient:
- Keep the most recent entry
- Flag older entries for removal
- Ask user if they want to update quantity on kept item

#### Custom Age Thresholds
Allow user to override default thresholds:
```
Which threshold would you like to adjust?
1. Meat/Seafood (default: 7 days)
2. Produce (default: 14 days)
3. Dairy (default: 30 days)
4. Bakery (default: 10 days)
```

#### Aisle Selection
Let user choose specific aisles to clean:
```
Which sections would you like to clean?
1. All perishables
2. Produce only
3. Dairy only
4. Meat/Seafood only
5. Custom selection
```

### 5. Safety Measures

- **Always confirm before deletion** - never auto-delete
- Show clear item details (name, ID, purchase date, age)
- Allow user to deselect specific items from batch
- Provide summary of what was removed

### 6. Final Report

After cleanup, show:
```
Pantry Cleanup Complete!

Removed:
- Produce: 15 items
- Dairy: 3 items
- Meat: 0 items

Total: 18 items removed

Remaining in-stock items: 421
```

---

## Implementation Notes

### Query Patterns
- Use `in_stock_only: false` to catch items already marked out of stock
- Order by `purchase_date` ascending (oldest first)
- Use `fields` to minimize data transfer

### Date Calculations
```python
from datetime import datetime

purchase_date = "2026-01-03T23:55:47"
purchase_dt = datetime.fromisoformat(purchase_date.replace('Z', '+00:00'))
age_days = (datetime.now() - purchase_dt).days
```

### Aisle Matching
- Note: Pantry has duplicate/inconsistent aisle names
  - "Spices & Seasonings" vs "Spices and Seasonings"
  - "Sauces & Condiments" vs "Sauces and Condiments"
- Use `by_aisle` param with LIKE matching to catch variations
- May need multiple queries per logical section

### Batch Operations
- MCP supports bulk updates: max 100 item_ids per call
- If >100 items to delete, chunk into batches

---

## User Experience

### Start Simple
Begin with basic workflow:
1. "I'll review your perishable items by section"
2. Show flagged items for one aisle at a time
3. Confirm deletion
4. Move to next aisle
5. Summary at end

### Progressive Disclosure
- Start with defaults
- Offer customization only if user asks or rejects suggestions
- Don't overwhelm with options upfront

### Clear Communication
- Always show WHY items are flagged (age, duplicate, out of stock)
- Use relative dates ("19 days ago") not just absolute dates
- Group by aisle for context
- Show item counts clearly

---

## Edge Cases

- **No purchase date**: Skip or flag for manual review
- **Recently added items**: Never flag items <3 days old
- **Empty aisles**: Skip with "No items found in [aisle]"
- **All items current**: "All [aisle] items are fresh (< X days old)"
- **API errors**: Gracefully handle and report
