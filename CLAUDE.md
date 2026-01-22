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
  skills/          # Claude Code skills
  tools/           # Helper functions
  scripts/         # Automation scripts
```
