# Paprika Assistant

Automation and tooling for managing Paprika recipes, pantry, and meal planning via Claude Code.

## Purpose

Claude Code skills and tools to interact with Paprika app data. Includes both interactive workflows and scheduled automation.

## MCP Integration

Paprika MCP server provides:
- **recipes**: Recipe management (search, create, update)
- **pantry**: Pantry tracking (inventory, expiration dates, aisle filtering)
- **meals**: Meal scheduling (weekly views, meal types, bulk scheduling)
- **menus**: Menu templates (read-only)

Call `action="help"` first on any MCP tool to discover available actions and parameters.

## Structure

```
paprika-assistant/
  .claude/
    agents/        # Claude Code agent definitions
    skills/        # Claude Code skills (project-level)
  scripts/         # Automation scripts
  logs/            # Automation logs (git-ignored)
```

## Skills

Project-level skills are stored in `.claude/skills/`. These skills are specific to this project and version-controlled with the repository.

**Available Skills:**
- **walmart-to-pantry**: Extract grocery items from Walmart orders and add to Paprika pantry with proper categorization and expiration dates
- **meal-planner**: (Additional skill for meal planning workflows)

**Skill Directory Locations:**
- Global skills (all projects): `~/.claude/skills/`
- Project skills (this repo): `.claude/skills/`

## Playwright Browser Setup

The walmart-to-pantry skill uses Playwright MCP for browser automation. Claude-in-Chrome does not work reliably in headless/remote sessions (macOS permission dialogs cannot be answered remotely).

### Persistent Session Configuration

Playwright is configured with three flags for bot detection resistance and session persistence:

- **Profile directory**: `~/.claude/playwright-profile/`
- **Stealth script**: `~/.claude/playwright-stealth.js`
- **Config file** (the one Claude Code actually reads): `~/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/playwright/.mcp.json`

The config should contain:
```json
{
  "playwright": {
    "command": "npx",
    "args": [
      "@playwright/mcp@latest",
      "--browser", "chrome",
      "--user-data-dir", "/Users/jonaheaton/.claude/playwright-profile",
      "--init-script", "/Users/jonaheaton/.claude/playwright-stealth.js"
    ]
  }
}
```

- `--browser chrome`: Use the real Chrome binary (better bot evasion than Chromium)
- `--user-data-dir`: Persist login session across Claude Code restarts
- `--init-script`: Inject stealth patches (see below) before any page script runs

**Note:** `--disable-features=AutomationControlled` (Playwright's default) is NOT the same as `--disable-blink-features=AutomationControlled` (the Blink-level patch). The stealth script patches `navigator.webdriver` in JavaScript as belt-and-suspenders.

**Important:** There is also a cache copy at `~/.claude/plugins/cache/claude-plugins-official/playwright/<hash>/.mcp.json` — editing this file has no effect. Only the marketplace file above is used at runtime.

### Re-login When Session Expires

When the Walmart session expires (~60 days), you need to be physically present at the Mac Mini to log in:

1. Temporarily add `"--headed"` to the marketplace config args
2. Restart Claude Code (the MCP server picks up the new config)
3. Navigate to `https://www.walmart.com/orders` — a visible browser window will open
4. Fill in email via Claude, type password directly in the browser window
5. After login succeeds, the session is already saved to `~/.claude/playwright-profile/` (since that's what `--user-data-dir` points to). No copy needed.
6. Remove `"--headed"` from the config
7. Verify session: check for cookies with `sqlite3 ~/.claude/playwright-profile/Default/Cookies "SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%walmart%'"`

### Verifying the Session

To confirm Walmart cookies are saved without restarting:
```bash
python3 -c "
import sqlite3
conn = sqlite3.connect('/Users/jonaheaton/.claude/playwright-profile/Default/Cookies')
rows = conn.execute(\"SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%walmart%'\").fetchone()
print(f'Walmart cookies: {rows[0]}')
conn.close()
"
```
20+ cookies = session is active.

### Stealth Script

`~/.claude/playwright-stealth.js` patches three fingerprinting signals that bot detection systems check:
- `navigator.webdriver` → `undefined` (hides automation flag)
- `navigator.plugins` → non-empty list (automation profiles often have 0 plugins)
- `navigator.languages` → `['en-US', 'en']` (realistic value)

Keep this script minimal — aggressive patches can break pages.

### Plugin Update Risk

If the playwright plugin auto-updates, it may overwrite the marketplace `.mcp.json`. To re-apply the full config:
```bash
cat > ~/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/playwright/.mcp.json << 'EOF'
{
  "playwright": {
    "command": "npx",
    "args": [
      "@playwright/mcp@latest",
      "--browser", "chrome",
      "--user-data-dir", "/Users/jonaheaton/.claude/playwright-profile",
      "--init-script", "/Users/jonaheaton/.claude/playwright-stealth.js"
    ]
  }
}
EOF
```

## Scheduled Automation

### Pantry Cleanup (Every Wednesday 3 AM)

Automatic cleanup of expired and duplicate pantry items using Claude Code in headless mode.

**Management:**
```bash
./scripts/install-scheduled-cleanup.sh install    # Enable scheduled job
./scripts/install-scheduled-cleanup.sh status     # Check job status
./scripts/install-scheduled-cleanup.sh run-now    # Run immediately
./scripts/install-scheduled-cleanup.sh uninstall  # Disable scheduled job
```

**Configuration:**
- Model: Haiku (cost-efficient)
- Permissions: `mcp__paprika__pantry` only
- Max turns: 20
- Logs: `logs/pantry-cleanup-*.log` and `logs/cleanup-history.log`

**Spoilage thresholds:**
- Meat/Seafood: 7 days
- Produce: 14 days
- Dairy: 30 days
- Bakery: 10 days
- Frozen: 180 days
