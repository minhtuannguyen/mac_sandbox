# mac-sandbox

Generic macOS sandbox wrapper for CLI tools. Enforces OS-level file write restrictions via `sandbox-exec`. Works with any CLI program — defaults to [OpenCode](https://opencode.ai).

## Install (OpenCode — default)

```bash
curl -fsSL https://raw.githubusercontent.com/minhtuannguyen/mac_sandbox/main/install.sh | bash
```

Installs `opencode-sandbox` to `~/.local/bin/` and creates `~/.config/mac-sandbox/opencode.json`.

## Install for another app

```bash
curl -fsSL https://raw.githubusercontent.com/minhtuannguyen/mac_sandbox/main/install.sh | bash -s -- --app claude
```

Installs `claude-sandbox` to `~/.local/bin/` and creates `~/.config/mac-sandbox/claude.json`.

Safe to re-run — updates the wrapper if a newer version is available, never overwrites your config.

## Configuration

Each app has its own config at **`~/.config/mac-sandbox/<app>.json`** (created on first install).

```json
{
  "$schema": "https://raw.githubusercontent.com/minhtuannguyen6868/opencode_sandbpx/main/schema.json",
  "sandbox_enabled": true,
  "allowed_directories": [
    "~/repositories/**"
  ],
  "state_dirs": [
    "~/.config/opencode/",
    "~/.local/share/opencode/",
    "~/.local/state/opencode/"
  ],
  "network": "full",
  "process_spawning": "allowed"
}
```

### Key fields

| Field | Purpose |
|-------|---------|
| `allowed_directories` | Paths the app may write to — your project directories. `**` glob supported. |
| `state_dirs` | Directories the app uses for its own config/data/state. Always writable inside the sandbox. |
| `program` | Override the binary name if it differs from the alias (e.g. `opencode-nightly`). |
| `sandbox_enabled` | Set to `false` to bypass the sandbox entirely (useful for debugging). |
| `temp_allowed` | Allow `/tmp` and `/var/tmp` writes (default: `true`). |
| `network` | `"full"` or `"none"` (default: `"full"`). |
| `process_spawning` | `"allowed"` or `"denied"` (default: `"allowed"`). |
| `deny_privilege_escalation` | Block `setuid`/capability changes (default: `true`). |

## How it works

```
opencode (alias)
  └─▶ opencode-sandbox        ← installed to ~/.local/bin/
        │  (mac-sandbox wrapper, app = inferred from filename)
        ├─ reads ~/.config/mac-sandbox/opencode.json
        ├─ generates a temporary .sb profile in /tmp
        ├─ launches: sandbox-exec -f profile.sb opencode
        └─ cleans up the .sb file on exit
```

The app name is inferred from the wrapper's own filename by stripping `-sandbox`:
`opencode-sandbox` → `opencode`, `claude-sandbox` → `claude`.

The sandbox uses a **deny-by-default** approach:
- `(deny default)` — block everything except explicitly allowed operations
- `(allow file-read*)` — allow reads everywhere (only write access is restricted)
- `(allow file-write*)` — re-open writes **only** for `allowed_directories`, `state_dirs`, and `/tmp`
- `(allow process-fork/exec*)` — only if `process_spawning: "allowed"`
- `(allow network*)` — only if `network: "full"`

The wrapper is stateless: it generates a fresh `.sb` profile on each run and deletes it on exit.

## Updating

Re-run the same install command:

```bash
curl -fsSL https://raw.githubusercontent.com/minhtuannguyen/mac_sandbox/main/install.sh | bash
```

The installer checksums the installed wrapper against the remote version and replaces it only if it changed. Your `~/.config/mac-sandbox/<app>.json` is always preserved.

## Limitations & Notes

### `sandbox-exec` deprecation

`sandbox-exec` is deprecated in macOS and may be removed in a future version. If Apple removes it, the wrapper will fall back to direct execution: `exec "$APP_BIN" "$@"`.