#Requires -Version 5.1
<#
.SYNOPSIS
    Aras Easy Installer -- interactive wizard that installs Aras Innovator
    natively on this Windows machine (SQL Server, IIS, ASP.NET Core, Aras).
.DESCRIPTION
    Run this script as Administrator. It walks you through every setting,
    detects what is already installed, and handles the rest.
.NOTES
    Supports any Aras Innovator version -- just point it at your extracted CD Image.
#>

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot

# -- Load modules --

$libPath = Join-Path $scriptRoot 'lib'
Import-Module (Join-Path $libPath 'Constants.psm1')  -Force -DisableNameChecking
Import-Module (Join-Path $libPath 'UI.psm1')         -Force -DisableNameChecking
Import-Module (Join-Path $libPath 'Scanner.psm1')    -Force -DisableNameChecking
Import-Module (Join-Path $libPath 'Preflight.psm1')  -Force -DisableNameChecking
Import-Module (Join-Path $libPath 'Install-IIS.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $libPath 'Install-SQL.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $libPath 'Install-Aras.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $libPath 'Uninstaller.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $libPath 'Repair.psm1')      -Force -DisableNameChecking

# ======================================================================
#  WIZARD
# ======================================================================

Clear-Host
Show-Banner

# -- Admin check --

if (-not (Test-Administrator)) {
    Show-Error 'This script must be run as Administrator.'
    Show-Info  'Right-click PowerShell and select "Run as administrator", then try again.'
    Write-Host ''
    Read-Host  '  Press Enter to exit'
    exit 1
}
Show-Success 'Running as Administrator'

# -- Pre-flight --

$preflight = Invoke-PreflightChecks

if (-not $preflight.Disk.Sufficient) {
    Show-Warn "Low disk space on C: ($($preflight.Disk.FreeGB) GB free, 10 GB recommended)"
    if (-not (Read-Confirm 'Continue anyway?')) { exit 0 }
} else {
    Show-Info "Disk space: $($preflight.Disk.FreeGB) GB free"
}

# ======================================================================
#  DETECT EXISTING INSTALLATION
# ======================================================================

$repairMode = $false
Show-Info 'Checking for existing Aras Innovator installation...'

$existing = Find-ExistingArasInstall
if ($existing) {
    $existingConfig = Read-InnovatorConfig -ConfigPath $existing.ConfigPath

    Show-Success 'Existing installation found!'
    Write-Host ''
    Show-KeyValue 'Install Dir'   $existing.InstallDir
    if ($existing.WebAlias) {
        Show-KeyValue 'Web Alias'     $existing.WebAlias
    }
    Show-KeyValue 'Config File'   $existing.ConfigPath
    if ($existingConfig.DbName) {
        Show-KeyValue 'Database'      $existingConfig.DbName
    }
    if ($existingConfig.LicenseKey) {
        Show-KeyValue 'License'       'Configured'
    } else {
        Show-KeyValue 'License'       'Not set'
    }

    # Show MAC addresses for licensing reference
    Write-Host ''
    Show-Info 'Network adapters (for Aras license key requests):'
    $macAddresses = Get-NetworkMacAddresses
    if ($macAddresses -and $macAddresses.Count -gt 0) {
        foreach ($adapter in $macAddresses) {
            Show-KeyValue "  $($adapter.Name)" $adapter.MacAddress
        }
    } else {
        Show-Info '  No active network adapters found'
    }

    Write-Host ''
    $repairMode = Read-Confirm -Prompt 'Repair/verify this installation?' -Default $true

    if ($repairMode) {
        Show-Step 'REPAIR' 'Diagnosing components'

        # -- Gather diagnostics --
        $diag = @{
            IIS      = $preflight.IIS.Enabled
            SqlRun   = $preflight.Sql.Running
            SqlInst  = $preflight.Sql.Installed
            Asp60    = (Test-AspNetCoreInstalled -MajorVersion '6.0').Installed
            Asp80    = (Test-AspNetCoreInstalled -MajorVersion '8.0').Installed
            SiteOk   = $false
        }

        $webAlias = $existing.WebAlias
        if (-not $webAlias) { $webAlias = 'InnovatorServer' }
        $siteUrl = "http://localhost/$webAlias"
        $health = Test-ArasSiteHealth -Url $siteUrl
        $diag.SiteOk = $health.Healthy

        # ASP.NET Core is only a real issue if the site returns 502 (ANCM failure)
        $aspNetIsIssue = (-not $diag.SiteOk -and $health.StatusCode -eq 502)

        # -- Display diagnostic table --
        $issueCount = 0

        function Write-DiagLine {
            param([string]$Component, [bool]$Ok, [string]$Detail, [bool]$IsIssue = $true)
            if ($Ok) {
                $status = '+ OK'
                $color  = 'Green'
            } elseif ($IsIssue) {
                $status = 'x ISSUE'
                $color  = 'Red'
                $script:issueCount++
            } else {
                $status = '- N/A'
                $color  = 'DarkGray'
            }
            $padded = $Component.PadRight(26)
            Write-Host "    $padded" -NoNewline -ForegroundColor DarkGray
            Write-Host $status -NoNewline -ForegroundColor $color
            if ($Detail) { Write-Host "  $Detail" -ForegroundColor DarkGray } else { Write-Host '' }
        }

        Write-DiagLine 'IIS Web Server'         $diag.IIS       ''
        Write-DiagLine 'SQL Server'              $diag.SqlRun    $(if ($diag.SqlInst -and -not $diag.SqlRun) { '(installed but stopped)' } elseif (-not $diag.SqlInst) { '(not installed)' } else { '' })
        Write-DiagLine 'ASP.NET Core 6.0'        $diag.Asp60     '' -IsIssue $aspNetIsIssue
        Write-DiagLine 'ASP.NET Core 8.0'        $diag.Asp80     '' -IsIssue $aspNetIsIssue
        Write-DiagLine 'Aras site responding'     $diag.SiteOk    $(if (-not $diag.SiteOk -and $health.StatusCode -gt 0) { "(HTTP $($health.StatusCode))" } elseif (-not $diag.SiteOk) { '(unreachable)' } else { '' })

        if ($issueCount -eq 0) {
            Write-Host ''
            Show-Success 'All components are healthy! Nothing to fix.'

            # Still offer license key update
            $doLicenseUpdate = $false
            if (-not $existingConfig.LicenseKey) {
                Write-Host ''
                $doLicenseUpdate = Read-Confirm -Prompt 'License key is not set. Add one now?' -Default $true
            } else {
                Write-Host ''
                $doLicenseUpdate = Read-Confirm -Prompt 'Update the license key?' -Default $false
            }

            if ($doLicenseUpdate) {
                $newLicKey = Read-OptionalInput -Prompt 'Aras License Key'
                $newActKey = Read-OptionalInput -Prompt 'Aras Activation Key'
                if ($newLicKey) {
                    $existingConfig.LicenseKey    = $newLicKey
                    $existingConfig.ActivationKey = $newActKey

                    $defaults = Get-InstallerDefaults
                    $repairConfig = @{
                        InstallDir    = $existing.InstallDir
                        VaultPath     = if ($existingConfig.VaultPath) { $existingConfig.VaultPath } else { Join-Path $existing.InstallDir 'Vault' }
                        DbName        = if ($existingConfig.DbName) { $existingConfig.DbName } else { $defaults.DbName }
                        SaPassword    = if ($existingConfig.DboPassword) { $existingConfig.DboPassword } else { '' }
                        AgentPort     = $existingConfig.AgentPort
                        WebAlias      = $webAlias
                        LicenseKey    = $newLicKey
                        ActivationKey = $newActKey
                    }
                    Write-InnovatorServerConfig -Config $repairConfig | Out-Null
                    Show-Info 'Restarting IIS to apply changes...'
                    & iisreset /restart 2>&1 | Out-Null
                    Show-Success 'License key updated'
                }
            }

            Show-Separator
            Write-Host ''
            Write-Host '  +===================================================+' -ForegroundColor Green
            Write-Host '  |                                                   |' -ForegroundColor Green
            Write-Host '  |         All good -- nothing to repair!            |' -ForegroundColor Green
            Write-Host '  |                                                   |' -ForegroundColor Green
            Write-Host '  +===================================================+' -ForegroundColor Green
            Write-Host ''
            Show-KeyValue 'Aras URL'    $siteUrl
            Show-KeyValue 'Admin login' 'admin / innovator'
            Show-KeyValue 'Root login'  'root  / innovator'
            Write-Host ''
            Read-Host '  Press Enter to exit'
            exit 0
        }

        # -- Issues found, offer to fix --
        Write-Host ''
        Show-Warn "$issueCount issue(s) found"

        if (-not (Read-Confirm 'Fix all issues?')) {
            Show-Info 'Cancelled. No changes were made.'
            exit 0
        }

        Show-Step 'REPAIR' 'Fixing issues'

        try {
            # Fix IIS
            if (-not $diag.IIS) {
                Show-Info 'Enabling IIS features...'
                Install-IISFeatures -Features (Get-IISFeatures) | Out-Null
            }

            # Fix SQL Server
            if ($diag.SqlInst -and -not $diag.SqlRun) {
                Show-Info 'Starting SQL Server...'
                Start-Service -Name 'MSSQLSERVER' -ErrorAction Stop
                Show-Success 'SQL Server started'
            } elseif (-not $diag.SqlInst) {
                Show-Warn 'SQL Server is not installed. Please re-run with a fresh install to set it up.'
            }

            # Fix ASP.NET Core -- only if site has a 502 (ANCM failure)
            if (-not $diag.SiteOk -and $health.StatusCode -eq 502) {
                if (-not $diag.Asp80) {
                    Show-Info 'Installing ASP.NET Core 8.0 Hosting Bundle...'
                    Install-AspNetCoreBundle -Version '8.0' | Out-Null
                }
                if (-not $diag.Asp60) {
                    Show-Info 'Installing ASP.NET Core 6.0 Hosting Bundle...'
                    Install-AspNetCoreBundle -Version '6.0' | Out-Null
                }
            }

            # If site not responding, try an iisreset
            if (-not $diag.SiteOk) {
                Show-Info 'Restarting IIS...'
                & iisreset /restart 2>&1 | Out-Null
                Start-Sleep -Seconds 3
            }

        } catch {
            Show-Error "Repair failed: $_"
            Write-Host ''
            Read-Host '  Press Enter to exit'
            exit 1
        }

        # License key update opportunity
        $configChanged = $false
        if (-not $existingConfig.LicenseKey) {
            Write-Host ''
            $doLicenseUpdate = Read-Confirm -Prompt 'License key is not set. Add one now?' -Default $true
            if ($doLicenseUpdate) {
                $newLicKey = Read-OptionalInput -Prompt 'Aras License Key'
                $newActKey = Read-OptionalInput -Prompt 'Aras Activation Key'
                if ($newLicKey) {
                    $defaults = Get-InstallerDefaults
                    $repairConfig = @{
                        InstallDir    = $existing.InstallDir
                        VaultPath     = if ($existingConfig.VaultPath) { $existingConfig.VaultPath } else { Join-Path $existing.InstallDir 'Vault' }
                        DbName        = if ($existingConfig.DbName) { $existingConfig.DbName } else { $defaults.DbName }
                        SaPassword    = if ($existingConfig.DboPassword) { $existingConfig.DboPassword } else { '' }
                        AgentPort     = $existingConfig.AgentPort
                        WebAlias      = $webAlias
                        LicenseKey    = $newLicKey
                        ActivationKey = $newActKey
                    }
                    Write-InnovatorServerConfig -Config $repairConfig | Out-Null
                    Show-Success 'License key saved'
                    $configChanged = $true
                }
            }
        }

        if ($configChanged) {
            Show-Info 'Restarting IIS to apply config changes...'
            & iisreset /restart 2>&1 | Out-Null
        }

        # Re-check health with retries (IIS needs warm-up time)
        Show-Separator
        Show-Info 'Waiting for IIS to warm up...'
        $health2 = @{ Healthy = $false }
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            Start-Sleep -Seconds 5
            Show-Info "Health check attempt $attempt/3..."
            $health2 = Test-ArasSiteHealth -Url $siteUrl
            if ($health2.Healthy) { break }
        }

        Show-Separator
        Write-Host ''
        if ($health2.Healthy) {
            Write-Host '  +===================================================+' -ForegroundColor Green
            Write-Host '  |                                                   |' -ForegroundColor Green
            Write-Host '  |         Repair complete -- site is healthy!       |' -ForegroundColor Green
            Write-Host '  |                                                   |' -ForegroundColor Green
            Write-Host '  +===================================================+' -ForegroundColor Green
        } else {
            Write-Host '  +===================================================+' -ForegroundColor Yellow
            Write-Host '  |                                                   |' -ForegroundColor Yellow
            Write-Host '  |     Repair complete (site still has issues)       |' -ForegroundColor Yellow
            Write-Host '  |                                                   |' -ForegroundColor Yellow
            Write-Host '  +===================================================+' -ForegroundColor Yellow
            if ($health2.StatusCode -eq 502) {
                Show-Warn 'HTTP 502 -- the ASP.NET Core version may still be wrong.'
                Show-Info  'Check which version Aras needs and install the correct hosting bundle.'
            }
        }

        Write-Host ''
        Show-KeyValue 'Aras URL'    $siteUrl
        Show-KeyValue 'Admin login' 'admin / innovator'
        Show-KeyValue 'Root login'  'root  / innovator'
        Write-Host ''
        Read-Host '  Press Enter to exit'
        exit 0
    }
    # If user chose No to repair, fall through to fresh install wizard below
}

Show-Info 'No existing installation detected (or skipped repair). Starting fresh install...'

# ======================================================================
#  STEP 1 -- Aras CD Image
# ======================================================================

Show-Step '1/7' 'Aras CD Image'

$cdImagePath = Read-TextInput -Prompt 'Path to your extracted Aras CD Image folder' -Validate {
    param($v)
    if (-not (Test-Path $v -PathType Container)) { return 'Folder does not exist' }
    return $null
}

Show-Info 'Scanning for installer files...'
$scan = Find-ArasMsiFiles -CdImagePath $cdImagePath

if ($scan.Error) {
    Show-Error $scan.Error
    Read-Host '  Press Enter to exit'
    exit 1
}

Show-Success "Found $($scan.MsiFiles.Count) MSI file(s)"
if ($scan.DetectedVersion) {
    Show-Info "Auto-detected version: $($scan.DetectedVersion)"
}

# Select MSI
$selectedMsi = $null
if ($scan.MsiFiles.Count -eq 1) {
    $m = $scan.MsiFiles[0]
    Show-Info "Installer: $($m.Name) ($(Format-FileSize $m.Size))"
    $selectedMsi = $m
} else {
    $msiOptions = $scan.MsiFiles | ForEach-Object {
        @{ Value = $_.Path; Label = $_.Name; Hint = (Format-FileSize $_.Size) }
    }
    $chosen = Read-Selection -Prompt 'Multiple MSI files found -- select the Aras installer:' -Options $msiOptions
    $selectedMsi = $scan.MsiFiles | Where-Object { $_.Path -eq $chosen }
}

$versionDefault = ''
if ($scan.DetectedVersion) { $versionDefault = $scan.DetectedVersion }
$arasVersion = Read-TextInput -Prompt 'Aras Innovator version label' -Default $versionDefault

# ======================================================================
#  STEP 2 -- SQL Server
# ======================================================================

Show-Step '2/7' 'SQL Server'

$installSql = $true
$sqlVersion = '2019'

if ($preflight.Sql.Installed) {
    $sqlStatus = 'stopped'
    if ($preflight.Sql.Running) { $sqlStatus = 'running' }
    Show-Info "Existing SQL Server detected ($sqlStatus, version $($preflight.Sql.Version))"
    $installSql = Read-Confirm -Prompt 'Install a fresh SQL Server anyway?' -Default $false

    if (-not $installSql -and -not $preflight.Sql.Running) {
        Show-Info 'Starting existing SQL Server service...'
        Start-Service -Name 'MSSQLSERVER' -ErrorAction SilentlyContinue
        Show-Success 'SQL Server started'
    }
}

if ($installSql) {
    $sqlVersion = Read-Selection -Prompt 'SQL Server version to install:' -DefaultValue '2019' -Options @(
        @{ Value = '2019'; Label = 'SQL Server 2019 Developer'; Hint = 'recommended' }
        @{ Value = '2022'; Label = 'SQL Server 2022 Developer' }
    )
}

$saPassword = Read-PasswordInput -Prompt 'SQL Server SA password' -RequireStrong

$defaults = Get-InstallerDefaults
$dbName = Read-TextInput -Prompt 'Database name' -Default $defaults.DbName

# ======================================================================
#  STEP 3 -- ASP.NET Core
# ======================================================================

Show-Step '3/7' 'ASP.NET Core Hosting Bundle'

$aspnetDefault = '6.0'
if ($arasVersion -match '(20[2-9]\d)') {
    $year = [int]$Matches[1]
    if ($year -ge 2025) { $aspnetDefault = '8.0' }
}
if ($aspnetDefault -eq '8.0') {
    Show-Info "Aras $arasVersion detected -- defaulting to ASP.NET Core 8.0"
}

$aspnetVersion = Read-Selection -Prompt 'ASP.NET Core Hosting Bundle:' -DefaultValue $aspnetDefault -Options @(
    @{ Value = '6.0';  Label = 'ASP.NET Core 6.0'; Hint = 'for Aras 2023/2024' }
    @{ Value = '8.0';  Label = 'ASP.NET Core 8.0'; Hint = 'for Aras 2025+' }
    @{ Value = 'none'; Label = 'Skip';             Hint = 'for older Aras versions' }
)

if ($aspnetVersion -ne 'none') {
    $aspCheck = Test-AspNetCoreInstalled -MajorVersion $aspnetVersion
    if ($aspCheck.Installed) {
        Show-Info "Already installed: $($aspCheck.Detail)"
    }
}

# ======================================================================
#  STEP 4 -- Aras Configuration
# ======================================================================

Show-Step '4/7' 'Aras Configuration'

$installDir = Read-TextInput -Prompt 'Install directory' -Default $defaults.InstallDir
$webAlias   = Read-TextInput -Prompt 'IIS Web Alias'     -Default $defaults.WebAlias
$vaultPath  = Read-TextInput -Prompt 'Vault folder'      -Default $defaults.VaultPath

# ======================================================================
#  STEP 5 -- Licensing (optional)
# ======================================================================

Show-Step '5/7' 'Licensing (optional)'

Show-Info 'You can set your license now, or leave blank and configure later'
Show-Info 'in InnovatorServerConfig.xml.'

$licenseKey    = Read-OptionalInput -Prompt 'Aras License Key'
$activationKey = Read-OptionalInput -Prompt 'Aras Activation Key'

# ======================================================================
#  STEP 6 -- Review
# ======================================================================

Show-Step '6/7' 'Review'

$config = @{
    ArasVersion    = $arasVersion
    MsiPath        = $selectedMsi.Path
    MsiName        = $selectedMsi.Name
    InstallSql     = $installSql
    SqlVersion     = $sqlVersion
    SaPassword     = $saPassword
    DbName         = $dbName
    AspNetVersion  = $aspnetVersion
    InstallDir     = $installDir
    WebAlias       = $webAlias
    VaultPath      = $vaultPath
    AgentPort      = $defaults.AgentPort
    LicenseKey     = $licenseKey
    ActivationKey  = $activationKey
}

$sqlLabel = 'Use existing'
if ($config.InstallSql) { $sqlLabel = "Install $($config.SqlVersion) Developer" }
$aspLabel = $config.AspNetVersion
if ($config.AspNetVersion -eq 'none') { $aspLabel = 'Skip' }
$licLabel = 'Not set (configure later)'
if ($config.LicenseKey) { $licLabel = 'Configured' }

Show-KeyValue 'Aras Version'    $config.ArasVersion
Show-KeyValue 'MSI Installer'   $config.MsiName
Show-KeyValue 'SQL Server'      $sqlLabel
Show-KeyValue 'Database'        $config.DbName
Show-KeyValue 'ASP.NET Core'    $aspLabel
Show-KeyValue 'Install Dir'     $config.InstallDir
Show-KeyValue 'Web Alias'       $config.WebAlias
Show-KeyValue 'Vault Path'      $config.VaultPath
Show-KeyValue 'License'         $licLabel

Write-Host ''
if (-not (Read-Confirm 'Proceed with installation?')) {
    Show-Info 'Cancelled. No changes were made.'
    exit 0
}

# ======================================================================
#  STEP 7 -- Install
# ======================================================================

Show-Step '7/7' 'Installing'

$stepNum = 0
$totalSteps = 1 + [int]$config.InstallSql + [int]($config.AspNetVersion -ne 'none') + 1 + 1

try {
    # -- IIS --
    $stepNum++
    Show-Info "[$stepNum/$totalSteps] IIS Features"
    if ($preflight.IIS.Enabled) {
        Show-Info 'IIS is already enabled, verifying features...'
    }
    $iisResult = Install-IISFeatures -Features (Get-IISFeatures)
    if (-not $iisResult) {
        Show-Warn 'Some IIS features failed, but continuing...'
    }

    # -- SQL Server --
    if ($config.InstallSql) {
        $stepNum++
        Show-Separator
        Show-Info "[$stepNum/$totalSteps] SQL Server $($config.SqlVersion)"
        Install-SqlServer -Version $config.SqlVersion -SaPassword $config.SaPassword | Out-Null
    }

    # -- ASP.NET Core --
    if ($config.AspNetVersion -ne 'none') {
        $stepNum++
        Show-Separator
        Show-Info "[$stepNum/$totalSteps] ASP.NET Core $($config.AspNetVersion)"
        Install-AspNetCoreBundle -Version $config.AspNetVersion | Out-Null
    }

    # -- Aras Innovator --
    $stepNum++
    Show-Separator
    Show-Info "[$stepNum/$totalSteps] Aras Innovator $($config.ArasVersion)"
    Install-ArasInnovator -Config $config | Out-Null

    # -- Config + Uninstaller --
    $stepNum++
    Show-Separator
    Show-Info "[$stepNum/$totalSteps] Configuration & cleanup"
    Write-InnovatorServerConfig -Config $config | Out-Null

    $uninstallPath = Join-Path $config.InstallDir 'Uninstall-Aras.ps1'
    New-UninstallScript -Config $config -OutputPath $uninstallPath | Out-Null
    Show-Success "Uninstall script saved to: $uninstallPath"

} catch {
    Show-Error "Installation failed: $_"
    Show-Info  'Check the error above and try running the script again.'
    Show-Info  'Partial installs can be cleaned up with the uninstall script if generated.'
    Write-Host ''
    Read-Host  '  Press Enter to exit'
    exit 1
}

# ======================================================================
#  HEALTH CHECK
# ======================================================================

Show-Separator
Show-Info 'Running post-install health check...'

$url = "http://localhost/$($config.WebAlias)"
$healthOk = $false
$health = @{ Healthy = $false; StatusCode = 0 }

for ($attempt = 1; $attempt -le 3; $attempt++) {
    Start-Sleep -Seconds 5
    Show-Info "Health check attempt $attempt/3..."
    $health = Test-ArasSiteHealth -Url $url
    if ($health.Healthy) { break }
}
$healthOk = $health.Healthy

if ($healthOk) {
    Show-Success "Site is responding at $url"
} elseif ($health.StatusCode -eq 502) {
    Show-Error "Site returned HTTP 502 -- ASP.NET Core module failure"
    Show-Warn  "This usually means the wrong ASP.NET Core Hosting Bundle version is installed."
    Show-Info  "You selected ASP.NET Core $($config.AspNetVersion), but Aras $($config.ArasVersion) may need a different version."
    Show-Info  "To fix: download the correct hosting bundle from https://dotnet.microsoft.com/download"
    Show-Info  "then run 'iisreset' in an admin PowerShell."
} else {
    Show-Warn "Could not reach $url"
    Show-Info  'IIS may still be starting up. Try opening the URL in a browser in a minute.'
}

# ======================================================================
#  DONE
# ======================================================================

Show-Separator

Write-Host ''
if ($healthOk) {
    Write-Host '  +===================================================+' -ForegroundColor Green
    Write-Host '  |                                                   |' -ForegroundColor Green
    Write-Host '  |         Installation complete!                    |' -ForegroundColor Green
    Write-Host '  |                                                   |' -ForegroundColor Green
    Write-Host '  +===================================================+' -ForegroundColor Green
} else {
    Write-Host '  +===================================================+' -ForegroundColor Yellow
    Write-Host '  |                                                   |' -ForegroundColor Yellow
    Write-Host '  |     Installation complete (with warnings)         |' -ForegroundColor Yellow
    Write-Host '  |                                                   |' -ForegroundColor Yellow
    Write-Host '  +===================================================+' -ForegroundColor Yellow
}
Write-Host ''

Show-KeyValue 'Aras URL'      $url
Show-KeyValue 'Admin login'   'admin / innovator'
Show-KeyValue 'Root login'    'root  / innovator'
Show-KeyValue 'Uninstaller'   $uninstallPath

if (-not $healthOk) {
    Write-Host ''
    Show-Info 'It may take a moment for IIS to start serving the application.'
}

if (-not $config.LicenseKey) {
    Write-Host ''
    Show-Warn 'Remember to add your license key to InnovatorServerConfig.xml'
    Show-Info  'Request one at: https://www.aras.com/en/support/licensekeyservice'
}

Write-Host ''
Read-Host '  Press Enter to exit'
