# Paprika Assistant

Automation and tooling for managing Paprika recipes, pantry, and meal planning via Claude Code.

## Current and archived workflows

- Paprika recipe, pantry and meal-planning MCP workflows remain available. The separate pantry-cleanup tooling is outside this retirement.
- **Archived 2026-11-05:** daily Walmart-delivery-to-pantry sync, its Gmail detection/import skills, and separate Playwright browser setup. The launchd job is disabled/unloaded and Claude's Playwright plugin is uninstalled.
- [Archived sync and retirement record](archive/walmart-sync/README.md). Old source is retained for reference, not an active task or permission to resume automation.

## Setup

1. Install [Claude Code CLI](https://claude.com/claude-code)
2. Configure Paprika MCP server in Claude settings
3. Clone this repository

## Usage

Includes Claude Code skills for interactive workflows and scripts for scheduled automation tasks.

## Structure

- `skills/` - Claude Code skills
- `tools/` - Helper functions
- `scripts/` - Automation scripts
