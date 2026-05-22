#requires -Version 5.1
$ErrorActionPreference = "Stop"

$InstallerDir = $PSScriptRoot
$ClaudeDir    = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
$ScriptSrc    = Join-Path $InstallerDir "statusline.sh"
$ScriptDst    = Join-Path $ClaudeDir "statusline.sh"
$Settings     = Join-Path $ClaudeDir "settings.json"

if (-not (Test-Path $ScriptSrc)) {
    Write-Error "statusline.sh not found at $ScriptSrc"
    exit 1
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error "node.exe not in PATH. Install Node.js first."
    exit 1
}

if (-not (Test-Path $ClaudeDir)) {
    New-Item -ItemType Directory -Path $ClaudeDir | Out-Null
}

$content   = [System.IO.File]::ReadAllText($ScriptSrc) -replace "`r`n", "`n"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($ScriptDst, $content, $utf8NoBom)
Write-Host "Installed: $ScriptDst"

$bashCandidates = @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files (x86)\Git\bin\bash.exe",
    (Join-Path $env:LOCALAPPDATA "Programs\Git\bin\bash.exe")
)
$bashPath = $bashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bashPath) {
    Write-Error "Git Bash not found. Install Git for Windows."
    exit 1
}

$cmdString = "`"$bashPath`" `"$ScriptDst`""

$nodeScript = @'
const fs = require("fs");
const p = process.env.SETTINGS_PATH;
let cfg = {};
if (fs.existsSync(p)) {
    try { cfg = JSON.parse(fs.readFileSync(p, "utf8")); } catch (e) {
        console.error("Failed to parse existing settings.json: " + e.message);
        process.exit(1);
    }
}
cfg.env = cfg.env || {};
cfg.env.FORCE_HYPERLINK = "1";
cfg.statusLine = { type: "command", command: process.env.STATUSLINE_CMD };
fs.writeFileSync(p, JSON.stringify(cfg, null, 2) + "\n");
console.log("Patched: " + p);
'@

$env:SETTINGS_PATH  = $Settings
$env:STATUSLINE_CMD = $cmdString
$tmpScript = [System.IO.Path]::GetTempFileName() + ".js"
[System.IO.File]::WriteAllText($tmpScript, $nodeScript)
try {
    node $tmpScript
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
    Remove-Item $tmpScript -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Done. Restart Claude Code to load the new status line."
