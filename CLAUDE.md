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
