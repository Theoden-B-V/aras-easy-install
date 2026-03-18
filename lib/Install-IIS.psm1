function Install-IISFeatures {
    param([string[]]$Features)

    Show-Info 'Enabling IIS and required Windows features...'
    Show-Info "($($Features.Count) features to enable -- this may take a few minutes)"

    $failed = @()
    $skipped = 0
    $enabled = 0

    foreach ($feature in $Features) {
        try {
            $state = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
            if ($state -and $state.State -eq 'Enabled') {
                $skipped++
                continue
            }

            Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -ErrorAction Stop | Out-Null
            $enabled++
        } catch {
            $failed += $feature
        }
    }

    # On Windows Server, DISM feature names may not all resolve. Fall back to
    # the ServerManager module which handles IIS as a server role.
    if ($failed.Count -gt 0) {
        $hasServerManager = Get-Command -Name 'Install-WindowsFeature' -ErrorAction SilentlyContinue
        if ($hasServerManager) {
            Show-Info 'Retrying failed features via ServerManager (Windows Server)...'
            try {
                Install-WindowsFeature -Name Web-Server -IncludeAllSubFeature -ErrorAction Stop | Out-Null
                Install-WindowsFeature -Name NET-Framework-45-ASPNET -ErrorAction SilentlyContinue | Out-Null
                $failed = @()
                $enabled++
                Show-Success 'IIS role installed via ServerManager'
            } catch {
                Show-Warn "ServerManager fallback failed: $_"
            }
        }
    }

    if ($skipped -gt 0) {
        Show-Info "$skipped feature(s) were already enabled"
    }
    if ($enabled -gt 0) {
        Show-Success "$enabled feature(s) newly enabled"
    }
    if ($failed.Count -gt 0) {
        Show-Warn "Failed to enable: $($failed -join ', ')"
        Show-Warn 'Some features may require a Windows reboot. Try again after restarting.'
        return $false
    }

    Show-Success 'All IIS features are enabled'
    return $true
}

Export-ModuleMember -Function Install-IISFeatures
