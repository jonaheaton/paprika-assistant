# Archived Walmart-to-Paprika sync

**Retired 2026-11-05 by explicit user decision. This is historical source, not an active workflow, backlog or authorization to restart it.**

The old job checked Gmail for Walmart delivery emails daily at 5 AM, read delivered order details using Playwright, and imported groceries into Paprika. A separate persistent browser was intended to support unattended remote runs without interactive browser-permission dialogs. The November 2–5 runs failed at Gmail detection before pantry import. These observations do not establish the date of the last successful import.

The separate default-cache Playwright browser found during diagnosis was owned by a long-running Claude Playwright MCP server. Its cache path differed from the historical profile documented here, so it cannot be conclusively attributed to this scheduled job. Multiple Chrome instances interfered with agent window selection; closing the identified automation instance resolved that incident.

## Retirement applied

- `com.jonaheaton.walmart-grocery-sync` has a persistent launchd disabled override and is unloaded. Its installed plist was moved out of `LaunchAgents` to `~/Library/LaunchAgents-Archived/2026-11-05/`.
- Claude's user setting `enabledPlugins["playwright@claude-plugins-official"]` is false. The previous settings file is backed up privately beside it.
- The identified old automation Chrome and Playwright MCP server were stopped; the regular signed-in Chrome remained running. The retired cache profile is recoverable from Trash.
- Gmail-detection and order-import skills moved out of `.claude/skills/` into this archive, preventing normal project skill discovery.
- Original scheduler scripts and plist moved here. Former script paths now exit with an archival notice; they cannot install or run the retired sync.
- Logs and import history remain in the private ignored `logs/` directory. No account content or browser profiles were committed.
- The separate Paprika MCP service, pantry cleanup, historical recipe-browser profile, and Walmart tooling's Python backend profiles were not retired by this change.

## Retained material

- [Original design](design.md)
- [Obsolete browser setup](browser-setup.md)
- [Historical troubleshooting](troubleshooting.md)
- [Original scripts and launchd template](scripts/)
- [Retired Gmail detection skill](skills/gmail-walmart-detector/SKILL.md)
- [Retired order-import skill](skills/walmart-to-pantry/SKILL.md)

Archived scripts remain executable source for audit and offline regression testing; their location and banners are not a security boundary. Running them deliberately can still perform their former actions. Current wrapper entrypoints are inert. Do not run archived source against live services or follow historical reinstallation instructions without a new explicit request and a fresh review of permissions, login/session handling and duplicate imports.

## Verification

Settings read-back showed the plugin disabled; `launchctl print-disabled gui/<uid>` showed the sync disabled; `launchctl print gui/<uid>/com.jonaheaton.walmart-grocery-sync` reported no loaded service. Native process inspection showed one main Chrome process and confirmed the old browser/server exited. Offline stub tests target the archived source and do not call Gmail, Walmart or Paprika.

Revival is not an active task. If explicitly requested in the future, review the archive first and make a new plan; do not simply enable the old timer or plugin. Current shopping uses the existing signed-in Chrome; operational troubleshooting lives in `~/wand/walmart-tools/docs/chrome-instance-troubleshooting.md`.

Retirement verification also confirmed both former shell entrypoints refuse execution (including installer `install` and `run-now`). Historical orchestrator regression tests passed 18/18 stub assertions after updating their source path.

## Plugin removal follow-up

Later in the same retirement session, the user requested actual plugin uninstallation in both Codex and Claude. Claude's supported plugin uninstall command succeeded; installed-plugin list, registry and enabled-plugin settings had no Playwright entry afterward. The residual plugin cache was moved to Trash. Codex's plugin-uninstall tool reported `not_installed`; its standalone MCP configuration also had no Playwright entry. This supersedes the earlier disabled-only state. Historical source, settings backups and the retired browser-profile copy remain archival; they do not constitute an installed plugin.
