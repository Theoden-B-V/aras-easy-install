$script:Accent     = 'Cyan'
$script:Highlight  = 'White'
$script:Dim        = 'DarkGray'
$script:StepColor  = 'Blue'
$script:ErrColor   = 'Red'
$script:OkColor    = 'Green'
$script:WarnColor  = 'Yellow'

# --- Banner ---

function Show-Banner {
    $lines = @(
        ''
        '  +===================================================+'
        '  |                                                   |'
        '  |         Aras Easy Installer  v2.0.0               |'
        '  |         Native PowerShell edition                  |'
        '  |                                                   |'
        '  +===================================================+'
        ''
    )
    foreach ($line in $lines) {
        Write-Host $line -ForegroundColor $script:Accent
    }
    Write-Host '  This wizard installs Aras Innovator directly on this' -ForegroundColor $script:Dim
    Write-Host '  machine -- SQL Server, IIS, and all dependencies.' -ForegroundColor $script:Dim
    Write-Host ''
}

# --- Step / section headers ---

function Show-Step {
    param([string]$Number, [string]$Title)
    Write-Host ''
    Write-Host "  -- Step $Number " -NoNewline -ForegroundColor $script:StepColor
    Write-Host $Title -ForegroundColor $script:Highlight
    Write-Host ''
}

# --- Messages ---

function Show-Info    { param([string]$Msg) Write-Host "  i $Msg" -ForegroundColor $script:Dim }
function Show-Success { param([string]$Msg) Write-Host "  + $Msg" -ForegroundColor $script:OkColor }
function Show-Warn    { param([string]$Msg) Write-Host "  ! $Msg" -ForegroundColor $script:WarnColor }
function Show-Error   { param([string]$Msg) Write-Host "  x $Msg" -ForegroundColor $script:ErrColor }

function Show-KeyValue {
    param([string]$Key, [string]$Value, [int]$Pad = 22)
    $paddedKey = $Key.PadRight($Pad)
    Write-Host "    $paddedKey" -NoNewline -ForegroundColor $script:Dim
    Write-Host $Value -ForegroundColor $script:Highlight
}

# --- Text input ---

function Read-TextInput {
    param(
        [string]$Prompt,
        [string]$Default = '',
        [scriptblock]$Validate = $null
    )
    while ($true) {
        if ($Default) {
            Write-Host "  ? $Prompt " -NoNewline -ForegroundColor $script:Accent
            Write-Host "[$Default]" -NoNewline -ForegroundColor $script:Dim
            Write-Host ': ' -NoNewline
        } else {
            Write-Host "  ? $Prompt" -NoNewline -ForegroundColor $script:Accent
            Write-Host ': ' -NoNewline
        }
        $input_val = Read-Host
        if ([string]::IsNullOrWhiteSpace($input_val) -and $Default) {
            $input_val = $Default
        }
        if ($Validate) {
            $err = & $Validate $input_val
            if ($err) {
                Show-Error $err
                continue
            }
        }
        if ([string]::IsNullOrWhiteSpace($input_val)) {
            Show-Error 'Value cannot be empty.'
            continue
        }
        return $input_val
    }
}

# --- Optional text input (can be empty) ---

function Read-OptionalInput {
    param(
        [string]$Prompt,
        [string]$Default = ''
    )
    if ($Default) {
        Write-Host "  ? $Prompt " -NoNewline -ForegroundColor $script:Accent
        Write-Host "[$Default]" -NoNewline -ForegroundColor $script:Dim
        Write-Host ': ' -NoNewline
    } else {
        Write-Host "  ? $Prompt " -NoNewline -ForegroundColor $script:Accent
        Write-Host '(leave blank to skip)' -NoNewline -ForegroundColor $script:Dim
        Write-Host ': ' -NoNewline
    }
    $input_val = Read-Host
    if ([string]::IsNullOrWhiteSpace($input_val)) { return $Default }
    return $input_val
}

# --- Password input ---

function Read-PasswordInput {
    param(
        [string]$Prompt,
        [switch]$RequireStrong
    )
    while ($true) {
        Write-Host "  ? $Prompt" -NoNewline -ForegroundColor $script:Accent
        Write-Host ': ' -NoNewline
        $secure = Read-Host -AsSecureString
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        )
        if ([string]::IsNullOrWhiteSpace($plain)) {
            Show-Error 'Password cannot be empty.'
            continue
        }
        if ($RequireStrong) {
            if ($plain.Length -lt 8)              { Show-Error 'Must be at least 8 characters.'; continue }
            if ($plain -cnotmatch '[A-Z]')        { Show-Error 'Must contain an uppercase letter.'; continue }
            if ($plain -cnotmatch '[a-z]')        { Show-Error 'Must contain a lowercase letter.'; continue }
            if ($plain -notmatch '\d')            { Show-Error 'Must contain a digit.'; continue }
            if ($plain -notmatch '[^A-Za-z0-9]')  { Show-Error 'Must contain a special character.'; continue }
        }
        return $plain
    }
}

# --- Arrow-key selection menu ---

function Read-Selection {
    param(
        [string]$Prompt,
        [array]$Options,
        [string]$DefaultValue = ''
    )

    Write-Host "  ? $Prompt" -ForegroundColor $script:Accent

    $idx = 0
    if ($DefaultValue) {
        for ($i = 0; $i -lt $Options.Count; $i++) {
            if ($Options[$i].Value -eq $DefaultValue) { $idx = $i; break }
        }
    }

    $startRow = [Console]::CursorTop

    function DrawMenu {
        [Console]::SetCursorPosition(0, $startRow)
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $label = $Options[$i].Label
            $hintText = ''
            if ($Options[$i].Hint) { $hintText = " ($($Options[$i].Hint))" }

            if ($i -eq $idx) {
                Write-Host "    > " -NoNewline -ForegroundColor $script:OkColor
                Write-Host $label -NoNewline -ForegroundColor $script:Highlight
                Write-Host $hintText -ForegroundColor $script:Dim
            } else {
                Write-Host "      $label" -NoNewline -ForegroundColor $script:Dim
                Write-Host $hintText -ForegroundColor $script:Dim
            }
        }
    }

    DrawMenu

    while ($true) {
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { if ($idx -gt 0) { $idx-- }; DrawMenu }
            'DownArrow' { if ($idx -lt $Options.Count - 1) { $idx++ }; DrawMenu }
            'Enter'     {
                Write-Host "    = $($Options[$idx].Label)" -ForegroundColor $script:OkColor
                return $Options[$idx].Value
            }
        }
    }
}

# --- Yes/No confirmation ---

function Read-Confirm {
    param(
        [string]$Prompt,
        [bool]$Default = $true
    )
    $hint = '[y/N]'
    if ($Default) { $hint = '[Y/n]' }
    Write-Host "  ? $Prompt $hint " -NoNewline -ForegroundColor $script:Accent
    $answer = Read-Host
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return ($answer.Trim().ToLower() -eq 'y')
}

# --- Progress indicator ---

function Show-Progress {
    param([string]$Activity, [int]$PercentComplete = -1)
    if ($PercentComplete -ge 0) {
        Write-Progress -Activity $Activity -PercentComplete $PercentComplete
    } else {
        Write-Progress -Activity $Activity
    }
}

function Hide-Progress {
    Write-Progress -Activity 'Done' -Completed
}

# --- Download with progress ---

function Start-Download {
    param([string]$Url, [string]$OutFile, [string]$Label)
    Show-Info "Downloading $Label..."
    $savedPref = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
        Show-Success "Downloaded $Label"
    } catch {
        if (Test-Path $OutFile) { Remove-Item $OutFile -Force -ErrorAction SilentlyContinue }
        throw "Failed to download ${Label}: $_"
    } finally {
        $ProgressPreference = $savedPref
    }
}

# --- Run external process with live output ---

function Start-ProcessWait {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$Label,
        [switch]$UseCmd
    )
    Show-Info "Running: $Label..."
    if ($UseCmd) {
        $argString = $ArgumentList -join ' '
        $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$FilePath`" $argString" `
            -Wait -PassThru -NoNewWindow -ErrorAction Stop
    } else {
        $proc = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList `
            -Wait -PassThru -NoNewWindow -ErrorAction Stop
    }
    if ($proc.ExitCode -ne 0) {
        throw "$Label failed with exit code $($proc.ExitCode)"
    }
    Show-Success "$Label completed"
}

# --- Separator ---

function Show-Separator {
    Write-Host ''
    Write-Host '  ------------------------------------------------------' -ForegroundColor $script:Dim
    Write-Host ''
}

Export-ModuleMember -Function Show-Banner, Show-Step, Show-Info, Show-Success, Show-Warn, Show-Error,
    Show-KeyValue, Read-TextInput, Read-OptionalInput, Read-PasswordInput, Read-Selection,
    Read-Confirm, Show-Progress, Hide-Progress, Start-Download, Start-ProcessWait, Show-Separator
