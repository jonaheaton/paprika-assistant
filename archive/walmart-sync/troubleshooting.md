> **ARCHIVED 2026-11-05.** Historical sync tests and failure modes. Paths below describe the former layout. Do not start the retired scheduler to reproduce them.

## Testing & Troubleshooting

### Running Tests

```bash
# Quick environment sanity checks (run after any plist/script change)
./scripts/install-walmart-sync.sh test

# Full orchestrator test suite (stub-based, no real APIs hit)
bash tests/test-orchestrator.sh
```

**Limitations of the above tests:** Both simulate launchd's stripped environment variables but not its resource limits (e.g., fd limit of 256). Tests run from a terminal inherit the shell's limits (typically 1024+), so failures caused by launchd's constraints won't be caught.

**True launchd simulation — trigger the job through launchd itself:**
```bash
launchctl start com.jonaheaton.walmart-grocery-sync
tail -f ~/Documents/paprika-assistant/logs/walmart-sync-$(date +%Y-%m-%d).log
```
This runs with launchd's real PATH, fd limits, and all other constraints — identical to the 5 AM scheduled run.

### Known Failure Modes

**`Operation not permitted` when running via launchd**
- Cause: macOS Full Disk Access (FDA) not granted to `/bin/bash`
- Symptom: `launchd-walmart-stderr.log` shows `getcwd: cannot access parent directories` and `Operation not permitted`; launchctl exit code 126
- Fix: System Settings → Privacy & Security → Full Disk Access → add `/bin/bash`
- Test: `./install-walmart-sync.sh test` (check 1 catches this)

**Empty `step1.json` or `step2.json` with no error logged**
- Cause: `claude -p` exits 0 but writes nothing — transient MCP init failure at boot
- Symptom: run log has only 2 lines; step JSON is 0 bytes; no Things task created
- Fix: now caught by JSON validation added after each claude call; creates a Things task
- Test: `bash tests/test-orchestrator.sh` (tests 1 and 7 cover this)

**`Another sync is already running` blocks all future runs**
- Cause: launchd killed the job with SIGKILL (after TimeOut), bypassing the EXIT trap that deletes the PID file; the PID was later recycled to an unrelated process
- Symptom: every run exits immediately with the "already running" message
- Fix: `rm logs/.walmart-sync.pid` — then the improved PID guard (checks process name) prevents recurrence
- Test: `bash tests/test-orchestrator.sh` (tests 5 and 6 cover this)

**`claude -p` fails with "low max file descriptors" error**
- Cause: launchd's default fd limit is 256 — too low for `claude -p` to open all MCP sockets
- Symptom: Things task created; step1 JSON contains `An unknown error occurred, possibly due to low max file descriptors`; may also manifest as a silent hang (socket open blocks instead of failing)
- Fix: `ulimit -n 65536` added to `walmart-grocery-sync.sh` (line 16); raises the limit for the script and all children before any MCP connections
- Note: not caught by `install-walmart-sync.sh test` or the stub test suite — use `launchctl start` to reproduce

**Gmail MCP token expired**
- Symptom: Things task created: "Gmail MCP token expired — re-authorize"
- Fix: Claude Code → `/mcp` to reconnect Gmail integration, or Settings → Integrations → Gmail

**Walmart session expired (Playwright)**
- Symptom: Things task created: "Walmart session expired — re-login required"
- Fix: See Playwright Browser Setup → Re-login When Session Expires above
