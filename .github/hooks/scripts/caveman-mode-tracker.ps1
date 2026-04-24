# caveman — Copilot CLI userPromptSubmitted hook (Windows PowerShell)
#
# Detects /caveman commands and natural-language activation/deactivation.
# Writes mode to flag file at ~/.copilot/.caveman-active.
#
# NOTE: Copilot CLI does not yet inject userPromptSubmitted hook output into
# the conversation. The flag write keeps the statusline badge in sync.
# Per-turn reinforcement is stubbed here — upgrade to emit additionalContext
# JSON when Copilot adds output support for this hook event.

$CopilotDir = Join-Path $HOME ".copilot"
$FlagPath   = Join-Path $CopilotDir ".caveman-active"

# Read stdin JSON
$Input = $null
try { $Input = [Console]::In.ReadToEnd() } catch {}
if (-not $Input) { exit 0 }

# Extract prompt
$Prompt = ""
try {
    $Data = $Input | ConvertFrom-Json
    $Prompt = if ($Data.prompt) { [string]$Data.prompt } else { "" }
    $Prompt = $Prompt.Trim().ToLowerInvariant()
} catch { exit 0 }

if (-not $Prompt) { exit 0 }

# Resolve default mode
$DefaultMode = ""
if ($env:CAVEMAN_DEFAULT_MODE) { $DefaultMode = $env:CAVEMAN_DEFAULT_MODE }
if (-not $DefaultMode) {
    $XdgConfig = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME ".config" }
    $ConfigPath = Join-Path $XdgConfig "caveman\config.json"
    if (-not (Test-Path $ConfigPath)) { $ConfigPath = Join-Path $env:APPDATA "caveman\config.json" }
    if (Test-Path $ConfigPath) {
        try {
            $cfg = Get-Content -Raw $ConfigPath | ConvertFrom-Json
            if ($cfg.defaultMode) { $DefaultMode = $cfg.defaultMode }
        } catch {}
    }
}
if (-not $DefaultMode) { $DefaultMode = "full" }
$DefaultMode = $DefaultMode.ToLowerInvariant() -replace '[^a-z0-9-]', ''
$ValidModes = @('off','lite','full','ultra','wenyan-lite','wenyan','wenyan-full','wenyan-ultra','commit','review','compress')
if ($ValidModes -notcontains $DefaultMode) { $DefaultMode = "full" }

function Write-Flag($mode) {
    if (-not (Test-Path $CopilotDir)) { New-Item -ItemType Directory -Path $CopilotDir -Force | Out-Null }
    if (Test-Path $FlagPath) {
        try {
            $Item = Get-Item -LiteralPath $FlagPath -Force
            if ($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return }
        } catch { return }
    }
    $Temp = Join-Path $CopilotDir ".caveman-active.$PID.$(Get-Date -Format 'yyyyMMddHHmmssfff')"
    try {
        [System.IO.File]::WriteAllText($Temp, $mode, [System.Text.Encoding]::UTF8)
        Move-Item -LiteralPath $Temp -Destination $FlagPath -Force
    } catch { Remove-Item -LiteralPath $Temp -ErrorAction SilentlyContinue }
}

function Delete-Flag {
    Remove-Item -LiteralPath $FlagPath -ErrorAction SilentlyContinue
}

# Natural-language activation
if ($Prompt -match '(activate|enable|turn on|start|talk like).*caveman|caveman.*(mode|activate|enable|turn on|start)') {
    if ($Prompt -notmatch '(stop|disable|turn off|deactivate)') {
        if ($DefaultMode -ne "off") { Write-Flag $DefaultMode }
    }
}

# /caveman slash commands
if ($Prompt -match '^/caveman') {
    $Parts = $Prompt -split '\s+'
    $Cmd = $Parts[0]
    $Arg = if ($Parts.Length -gt 1) { $Parts[1] } else { "" }
    $Mode = $null

    switch ($Cmd) {
        '/caveman-commit'   { $Mode = "commit" }
        '/caveman-review'   { $Mode = "review" }
        '/caveman-compress' { $Mode = "compress" }
        '/caveman:caveman-compress' { $Mode = "compress" }
        { $_ -in '/caveman','/caveman:caveman' } {
            $Mode = switch ($Arg) {
                'lite'         { "lite" }
                'ultra'        { "ultra" }
                'wenyan-lite'  { "wenyan-lite" }
                'wenyan'       { "wenyan" }
                'wenyan-full'  { "wenyan" }
                'wenyan-ultra' { "wenyan-ultra" }
                default        { $DefaultMode }
            }
        }
    }

    if ($null -ne $Mode) {
        if ($Mode -ne "off") { Write-Flag $Mode }
        else { Delete-Flag }
    }
}

# Natural-language deactivation
if ($Prompt -match '(stop|disable|deactivate|turn off).*caveman|caveman.*(stop|disable|deactivate|turn off)|normal mode') {
    Delete-Flag
}

# NOTE: Per-turn reinforcement stub.
# When Copilot adds output support for userPromptSubmitted, emit:
#   '{"additionalContext": "CAVEMAN MODE ACTIVE (...). Drop articles/filler/pleasantries/hedging. ..."}'
# Read flag here and output JSON. For now, exit cleanly.
exit 0
