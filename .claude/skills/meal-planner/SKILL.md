---
name: meal-planner
description: Weekly meal planning for a kosher household with working parents. Use when the user asks to plan meals for the week, create a weekly meal plan, schedule lunches or dinners, or needs help organizing meals. Integrates with Paprika recipe app to analyze pantry inventory, review past meals, suggest new meal ideas, and schedule meals to the calendar.
---

# Weekly Meal Planner

This skill helps plan a week's worth of meals for a kosher household with two working parents and a young child (Brooke). It balances nutrition, variety, convenience, and family preferences while leveraging the Paprika recipe management system.

## Planning Goals

**Weekly meal targets:**
- **Brooke's weekday lunches** (Monday-Friday): 5 complete lunches
- **Family dinners**: 3-4 dinners per week (weeknights)

**Each meal must meet these criteria:**
- Kosher compliant
- Low to medium complexity (suitable for working parents)
- Prep-ahead friendly where possible
- Age-appropriate for young children
- Provides balanced nutrition

## Workflow

Follow these steps in order. Display progress to the user as you work through them.

### Step 1: Review Past Meals (2+ weeks)

Check what was scheduled in the past 2-4 weeks to understand recent patterns and avoid immediate repetition.

```
Use: Paprika Recipes:meals with action="list"
Look back: 2-4 weeks from current date
Focus on: Dinner and Lunch meal types
```

**Analysis to perform:**
- Identify dinners from the past 2 weeks (avoid repeating these)
- Note successful meals from 2+ weeks ago (these are good candidates to repeat)
- Look for protein rotation patterns (beef, chicken, fish, plant-based)
- Check vegetable variety
- Identify any meal prep patterns (e.g., batch cooking, freezer meals)

### Step 2: Check Pantry Inventory

Review current pantry stock to inform meal planning and identify what needs to be purchased.

```
Use: Paprika Recipes:pantry with action="query"
Parameters: in_stock_only=true, fields=["aisle_name", "quantity"]
```

**Key pantry categories to check:**
- **Proteins**: Frozen items (Beyond Meat products, Daring chicken, fish fillets), canned beans, eggs, tofu
- **Vegetables**: Fresh and frozen vegetables
- **Grains/Starches**: Pasta, rice, bread, tortillas, crackers
- **Dairy**: Yogurt, cheese varieties, milk
- **Convenience items**: Frozen quiches, veggie burgers, other prepared items

**Make note of:**
- Available proteins that can anchor meals
- Vegetables that need to be used soon
- Grains and starches for side dishes
- Items running low that should be replenished

### Step 3: Search Highly-Rated Recipes

Find recipe inspiration from the user's collection of tried-and-tested favorites.

```
Use: Paprika Recipes:recipes with action="query"
Parameters: min_rating=4, fields=["rating", "total_time", "categories"]
```

**Prioritize recipes that are:**
- Rated 4+ stars (proven family favorites)
- Tagged "Quick" or "Freezer Meals" for busy weeknights
- Include prep-ahead components
- Use ingredients already in pantry

**Recipe categories that work well:**
- Fish (quick cooking, healthy)
- Asian (versatile, often one-pot)
- Soups (batch cooking, freezer-friendly)
- Pastas (kid-friendly, filling)
- Veggies (sides that can be prepped ahead)

### Step 4: Generate Meal Ideas

Create meal suggestions that follow established patterns and best practices.

#### Brooke's Lunch Format

Use this proven format: "Brooke's Lunch: [protein], with [vegetable], [fruit], and [pouch type]"

**Component rotation guidelines:**

*Protein options (rotate throughout week):*
- Tuna salad sandwich
- Salmon sandwich
- Cheese sandwich
- Hard boiled egg
- String cheese + crackers
- Hummus with pita

*Vegetable options (rotate daily):*
- Cucumber slices
- Carrot sticks
- Cherry tomatoes
- Bell pepper strips
- Celery sticks

*Fruit options (rotate daily):*
- Apple slices
- Grapes
- Berries
- Banana
- Orange segments
- Melon cubes

*Grain component:*
- Whole grain bread (sandwich)
- Whole grain crackers
- Pita bread
- Whole grain bagel

*Always include:*
- One fruit-vegetable pouch (consistent item)

**Example:** "Brooke's Lunch: Tuna Salad Sandwich, with Cucumber, Apples, and Vegetable Pouch"

#### Family Dinner Format

Use this simple format: "[Protein] + [Vegetable] + [Starch/Grain]" OR link to a specific recipe.

**Protein rotation (across the week):**
- Fish (1-2x/week): Salmon, cod, battered fish
- Plant-based (1-2x/week): Beyond Meat, Daring chicken, tofu
- Traditional proteins: Chicken schnitzel, steak
- Egg-based: Quiche, frittata
- Legume-based: Beans, lentil soup

**Vegetable variety (aim for color diversity):**
- Green: Broccoli, green beans, asparagus, Brussels sprouts
- Orange: Butternut squash, carrots, bell peppers
- Other: Cauliflower, cabbage, bok choy

**Starch/Grain options:**
- Pasta (various shapes, whole wheat options)
- Rice (white, brown, flavored)
- Potatoes (roasted, mashed, waffle fries)
- Bread/rolls
- Quinoa

**Dinner planning principles:**
1. **Prep-ahead strategy**: Identify components that can be prepared 1-2 days in advance
   - Vegetables can be chopped/washed ahead
   - Grains can be cooked and reheated
   - Marinades can be prepared in advance
   - Some proteins can be partially prepped

2. **Convenience balance**: Mix from-scratch meals with strategic convenience items
   - 2-3 meals: Fresh cooking with simple prep
   - 1-2 meals: Leverage frozen proteins or convenience items
   - Consider: Frozen pizza, frozen quiches, frozen fish for busy nights

3. **Variety across the week**:
   - Different protein sources each night
   - Color variety in vegetables
   - Mix of cooking methods (oven, stovetop, air fryer)
   - Balance of cuisines (American, Asian, Mediterranean, etc.)

4. **Recipe integration**:
   - Link to highly-rated recipes when using them
   - For simple combinations, describe components without recipe link
   - Mark prep-intensive recipes for less busy nights

**Example dinners:**
- "Garlic Butter Salmon + Asparagus + Roasted Potatoes" (links to recipe #358)
- "Beyond Meat Beef Crumble with Rice and Carrots"
- "Frozen Spinach Quiche with Side Green Salad"
- "Crispy Air Fryer Tofu + Bok Choy + Rice Noodles"

### Step 5: Present Options to User

**Before scheduling anything**, present meal ideas to the user for discussion and approval.

Format your presentation as:

**BROOKE'S LUNCHES (Mon-Fri):**
- Monday: [Complete lunch description]
- Tuesday: [Complete lunch description]
- Wednesday: [Complete lunch description]
- Thursday: [Complete lunch description]
- Friday: [Complete lunch description]

**FAMILY DINNERS (3-4 nights):**
- [Day]: [Complete dinner description] - *Prep notes: [any advance prep possible]*
- [Day]: [Complete dinner description] - *Prep notes: [any advance prep possible]*
- [Day]: [Complete dinner description] - *Prep notes: [any advance prep possible]*
- [Day]: [Complete dinner description] - *Prep notes: [any advance prep possible]*

**GROCERY LIST:**
Items needed that aren't currently in pantry:
- [Aisle]: [items]
- [Aisle]: [items]

**DISCUSSION QUESTIONS:**
- Does this variety work for your week?
- Any nights where you'd prefer a different protein or vegetable?
- Any dietary needs or preferences to adjust for this week?

### Step 6: Schedule Approved Meals

Once the user approves the meal plan (or requests specific modifications), schedule meals to Paprika.

**Get meal type IDs first:**
```
Use: Paprika Recipes:meals with action="types"
Typical IDs: Lunch (varies), Dinner (varies)
```

**Schedule in bulk:**
```
Use: Paprika Recipes:meals with action="schedule"
Parameter: meals=[{date, meal_type_id, name, recipe_id (if applicable)}]
```

**Scheduling guidelines:**
- Use ISO format dates (YYYY-MM-DD)
- Include recipe_id when meal is based on a specific recipe
- Use descriptive names that match the format shown above
- Set appropriate meal_type_id (Lunch for Brooke's lunches, Dinner for dinners)
- Can schedule up to 100 meals in a single bulk operation

**Confirm with user:**
"✅ Scheduled [X] meals to your Paprika calendar for the week of [date]. Your meals are ready to go!"

### Step 7: Grocery List Finalization

Present the final grocery list organized by aisle.

**If user wants to add to Apple Reminders:**
Ask: "Would you like me to add these items to your 'Grocery List' in Apple Reminders?"
(Note: This requires separate integration - document what's needed but don't implement)

## Best Practices

**Variety and Rotation:**
- Don't repeat the same lunch protein two days in a row
- Aim for different colored vegetables each day
- Rotate between protein categories (fish, plant-based, traditional)
- Mix familiar favorites with occasional new recipes

**Family-Friendly Considerations:**
- Toddler-appropriate textures and flavors
- Options for picky eaters (plain alternatives)
- Finger-food friendly when possible
- Moderate spice levels

**Working Parent Reality:**
- Total hands-on dinner prep should be ≤45 minutes
- Include 1-2 "easy nights" with convenience items
- Prep-ahead components maximize efficiency
- Weekend prep suggestions when beneficial

**Kosher Compliance:**
- No mixing meat and dairy
- Use kosher-certified products
- Appropriate protein sources

**Pantry Optimization:**
- Prioritize using items already in stock
- Plan meals that share ingredients
- Note items nearing expiration
- Minimize waste through smart planning

## Common Meal Ideas

**Quick Weeknight Dinners (30-40 min):**
- Salmon + roasted vegetables + rice
- Pasta with vegetables and sauce
- Stir-fry with tofu/Beyond Meat + vegetables + noodles/rice
- Fish tacos with slaw and beans
- Quiche with side salad

**Prep-Ahead Friendly:**
- Soups (make ahead, reheat)
- Grain bowls (components prepped separately)
- Sheet pan meals (vegetables can be prepped ahead)
- Pasta bakes (can assemble in advance)

**Plant-Based Favorites:**
- Beyond Meat beef crumble with rice and vegetables
- Crispy tofu with Asian vegetables
- Bean-based soups and chilis
- Veggie burgers with sides

## Troubleshooting

**If pantry inventory is sparse:**
- Suggest more grocery items
- Pivot to recipes requiring fewer fresh ingredients
- Recommend stocking key frozen proteins and vegetables

**If recent meals show low variety:**
- Actively introduce new protein sources
- Suggest different cuisines
- Recommend trying a new highly-rated recipe

**If user has limited prep time this week:**
- Increase ratio of convenience meals
- Focus on one-pot/sheet pan dinners
- Suggest all components can be made simultaneously

**If ingredients are unavailable:**
- Offer substitutions from pantry
- Adjust recipes to work with what's on hand
- Note alternatives on grocery list
