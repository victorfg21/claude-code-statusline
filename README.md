# Claude Code Status Line

A rich status line for Claude Code showing working directory, git status, context usage, cost, duration, lines changed, rate limits, model, and an optional `[CAVEMAN]` badge when the [Caveman plugin](https://github.com/JuliusBrussee/caveman) is active.

## Preview

Wide layout (terminal >= 100 cols), 2 lines:

```
 ~/project on main +5 ~2 nordware/console
 ▓▓░░░░░░░░ 16% 165k/1.0M  $0.15  12m  +156-23  5h:24% 7d:41%  Opus  [CAVEMAN] 30
```

Narrow layout (< 100 cols), 3 lines:

```
 ~/project on main +5 ~2
 ▓▓░░░░░░░░ 16% 165k/1.0M  $0.15  12m
 +156-23  5h:24% 7d:41%  Opus  [CAVEMAN] 30
```

The directory and the repo label are clickable hyperlinks (Ctrl+click).

## Requirements

- **Node.js** in `PATH` — used to parse the JSON Claude Code sends on stdin
- **git** in `PATH` — for branch / dirty / remote indicators
- A terminal with ANSI color support (Windows Terminal, iTerm2, Kitty, WezTerm, etc.)
- **Windows only**: Git for Windows (the installer uses Git Bash to run the script)

## Quick install (one-liner)

### Linux / macOS / Git Bash

```bash
curl -fsSL https://github.com/victorfg21/claude-code-statusline/archive/refs/heads/main.tar.gz \
  | tar -xz -C /tmp \
  && bash /tmp/claude-code-statusline-main/install.sh
```

### Windows (PowerShell)

```powershell
$tmp = "$env:TEMP\cc-statusline"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Path $tmp | Out-Null
Invoke-WebRequest "https://github.com/victorfg21/claude-code-statusline/archive/refs/heads/main.zip" -OutFile "$tmp\src.zip"
Expand-Archive "$tmp\src.zip" $tmp -Force
& powershell -ExecutionPolicy Bypass -File (Get-ChildItem "$tmp\*\install.ps1").FullName
```

## Manual install (clone)

```bash
git clone https://github.com/victorfg21/claude-code-statusline.git
cd claude-code-statusline
```

### Linux / macOS / Git Bash

```bash
bash install.sh
```

### Windows (PowerShell)

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

The installer copies `statusline.sh` to `~/.claude/statusline.sh`, then patches `~/.claude/settings.json` with the right `statusLine.command` for your platform and adds `FORCE_HYPERLINK=1` to `env`. Existing settings are preserved.

After install, restart Claude Code (`/exit`, then reopen).

## Layout

| Segment        | Source                                |
|----------------|---------------------------------------|
| Working dir    | `workspace.current_dir`               |
| Git branch     | `git symbolic-ref HEAD`               |
| Staged / mod   | `git diff --cached`, `git diff`       |
| Repo link      | `git remote get-url origin`           |
| Context bar    | `context_window.current_usage`        |
| Cost           | `cost.total_cost_usd`                 |
| Duration       | `cost.total_duration_ms`              |
| Lines changed  | `cost.total_lines_added/removed`      |
| 5h / 7d limits | `rate_limits.five_hour/seven_day`     |
| Model          | `model.display_name`                  |
| Caveman badge  | `~/.claude/.caveman-active` (if file exists and content is a valid mode) |

## Color thresholds

Context: green < 70%, yellow 70 to 89%, red >= 90%.
Rate limit: green < 50%, yellow 50 to 79%, red >= 80%.

## Caveman integration

If the [Caveman plugin](https://github.com/JuliusBrussee/caveman) writes a mode flag to `~/.claude/.caveman-active`, the status line appends an orange badge such as `[CAVEMAN]`, `[CAVEMAN:ULTRA]`, or `[CAVEMAN:LITE]`. The optional savings indicator from `~/.claude/.caveman-statusline-suffix` is appended after the badge. Set `CAVEMAN_STATUSLINE_SAVINGS=0` in `env` to hide the savings number.

When Caveman is not installed, no badge renders and the status line behaves as a normal panel.

## Troubleshooting

| Symptom                              | Cause                                       | Fix                                       |
|--------------------------------------|---------------------------------------------|-------------------------------------------|
| Tokens, cost, duration all zero      | `node` not on Claude Code's `PATH`          | Install Node.js or add to PATH            |
| Bar characters render as `?`         | Terminal lacks UTF-8                        | Use a UTF-8 terminal                      |
| Hyperlinks not clickable             | Terminal lacks OSC 8 support                | Use Windows Terminal / iTerm2 / WezTerm   |
| Status line missing                  | Script not executable (Unix only)           | `chmod +x ~/.claude/statusline.sh`        |
| `[CAVEMAN]` badge stuck after stop   | Stale `~/.claude/.caveman-active`           | `rm ~/.claude/.caveman-active`            |
| Rate limits show `--`                | Free / Pro plan, or first response pending  | Expected; appears once API returns the field |

## Uninstall

Remove the `statusLine` block from `~/.claude/settings.json` and delete `~/.claude/statusline.sh`.
