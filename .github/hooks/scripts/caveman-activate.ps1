# caveman — Copilot CLI sessionStart hook (Windows PowerShell)
#
# Runs on every session start:
#   1. Writes flag file at ~/.copilot/.caveman-active (statusline reads this)
#   2. Emits caveman ruleset as {"additionalContext": "..."} JSON
#      (Copilot CLI v1.0.11+ injects this into the conversation)
#   3. Detects missing statusline config and emits setup nudge

$ProjectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Location).Path }
$SkillPath  = Join-Path $ProjectDir ".github\skills\caveman\SKILL.md"
$CopilotDir = Join-Path $HOME ".copilot"
$FlagPath   = Join-Path $CopilotDir ".caveman-active"
$SettingsPath = Join-Path $CopilotDir "settings.json"

# Resolve mode: env var → config file → default "full"
$Mode = ""
if ($env:CAVEMAN_DEFAULT_MODE) { $Mode = $env:CAVEMAN_DEFAULT_MODE }
if (-not $Mode) {
    $XdgConfig = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME ".config" }
    $ConfigPath = Join-Path $XdgConfig "caveman\config.json"
    if (-not (Test-Path $ConfigPath)) {
        $ConfigPath = Join-Path $env:APPDATA "caveman\config.json"
    }
    if (Test-Path $ConfigPath) {
        try {
            $cfg = Get-Content -Raw $ConfigPath | ConvertFrom-Json
            if ($cfg.defaultMode) { $Mode = $cfg.defaultMode }
        } catch {}
    }
}
if (-not $Mode) { $Mode = "full" }
$Mode = $Mode.ToLowerInvariant() -replace '[^a-z0-9-]', ''

$ValidModes = @('off','lite','full','ultra','wenyan-lite','wenyan','wenyan-full','wenyan-ultra','commit','review','compress')
if ($ValidModes -notcontains $Mode) { $Mode = "full" }

# "off" mode — skip activation
if ($Mode -eq "off") {
    Remove-Item -LiteralPath $FlagPath -ErrorAction SilentlyContinue
    exit 0
}

# Write flag file (refuse reparse points, atomic)
if (-not (Test-Path $CopilotDir)) { New-Item -ItemType Directory -Path $CopilotDir -Force | Out-Null }
$IsReparsePoint = $false
if (Test-Path $FlagPath) {
    try {
        $Item = Get-Item -LiteralPath $FlagPath -Force
        if ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { $IsReparsePoint = $true }
    } catch {}
}
if (-not $IsReparsePoint) {
    $TempPath = Join-Path $CopilotDir ".caveman-active.$PID.$(Get-Date -Format 'yyyyMMddHHmmssfff')"
    try {
        [System.IO.File]::WriteAllText($TempPath, $Mode, [System.Text.Encoding]::UTF8)
        Move-Item -LiteralPath $TempPath -Destination $FlagPath -Force
    } catch { Remove-Item -LiteralPath $TempPath -ErrorAction SilentlyContinue }
}

# Handle independent modes
if (@('commit','review','compress') -contains $Mode) {
    $JsonOut = [PSCustomObject]@{ additionalContext = "CAVEMAN MODE ACTIVE — level: $Mode. Behavior defined by /caveman-$Mode skill." } | ConvertTo-Json -Compress
    Write-Output $JsonOut
    exit 0
}

# Resolve wenyan alias
$ModeLabel = $Mode
if ($Mode -eq "wenyan") { $ModeLabel = "wenyan-full" }

# Statusline nudge
$Nudge = ""
$HasStatusline = $false
if (Test-Path $SettingsPath) {
    try {
        $settings = Get-Content -Raw $SettingsPath | ConvertFrom-Json
        if ($null -ne $settings.statusLine) { $HasStatusline = $true }
    } catch {}
}
if (-not $HasStatusline) {
    $StatuslineScript = Join-Path $CopilotDir "hooks\copilot-statusline.ps1"
    $Cmd = "powershell -ExecutionPolicy Bypass -File `"$StatuslineScript`""
    $Nudge = "STATUSLINE SETUP NEEDED: The caveman hooks include a statusline badge showing active mode (e.g. [CAVEMAN], [CAVEMAN:ULTRA]). It is not configured yet. To enable, add to ~/.copilot/settings.json: ""statusLine"": { ""type"": ""command"", ""command"": ""$Cmd"" }. Proactively offer to set this up for the user on first interaction."
}

# Build output from SKILL.md, filtered to active intensity level
$Text = ""
if (Test-Path $SkillPath) {
    try {
        $content = Get-Content -Raw -LiteralPath $SkillPath
        # Strip YAML frontmatter
        $body = $content -replace '^---[\s\S]*?---\s*', ''
        $lines = $body -split "`n"
        $outLines = @()
        foreach ($line in $lines) {
            if ($line -match '^\|\s*\*\*(\S+?)\*\*\s*\|') {
                if ($Matches[1] -eq $ModeLabel) { $outLines += $line }
                continue
            }
            if ($line -match '^- (\S+?):\s') {
                if ($Matches[1] -eq $ModeLabel) { $outLines += $line }
                continue
            }
            $outLines += $line
        }
        $Text = "CAVEMAN MODE ACTIVE — level: $ModeLabel`n`n" + ($outLines -join "`n")
    } catch {}
}
if (-not $Text) {
    $Text = "CAVEMAN MODE ACTIVE — level: $ModeLabel`n`nRespond terse like smart caveman. All technical substance stay. Only fluff die.`n`n## Persistence`n`nACTIVE EVERY RESPONSE. No revert after many turns. No filler drift. Still active if unsure. Off only: 'stop caveman' / 'normal mode'.`n`n## Rules`n`nDrop: articles (a/an/the), filler (just/really/basically), pleasantries, hedging. Fragments OK. Short synonyms. Technical terms exact. Code blocks unchanged.`n`nPattern: [thing] [action] [reason]. [next step].`n`n## Auto-Clarity`n`nDrop caveman for: security warnings, irreversible action confirmations, user confused. Resume after.`n`n## Boundaries`n`nCode/commits/PRs: write normal. 'stop caveman' or 'normal mode': revert. Level persist until changed or session end."
}
if ($Nudge) { $Text = $Text + "`n`n" + $Nudge }

$JsonOut = [PSCustomObject]@{ additionalContext = $Text } | ConvertTo-Json -Compress
Write-Output $JsonOut
