function Test-Administrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-SqlServerInstalled {
    $service = Get-Service -Name 'MSSQLSERVER' -ErrorAction SilentlyContinue
    if ($service) {
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
        $version = ''
        try {
            $instances = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            if ($instances.MSSQLSERVER) {
                $instPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$($instances.MSSQLSERVER)\Setup"
                $setup = Get-ItemProperty -Path $instPath -ErrorAction SilentlyContinue
                if ($setup.Version) { $version = $setup.Version }
            }
        } catch {}

        return @{
            Installed = $true
            Running   = $service.Status -eq 'Running'
            Version   = $version
        }
    }
    return @{ Installed = $false; Running = $false; Version = '' }
}

function Test-IISEnabled {
    # DISM approach (works on Windows 10/11 and most Server editions)
    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName 'IIS-WebServer' -ErrorAction SilentlyContinue
        if ($feature -and $feature.State -eq 'Enabled') {
            return @{ Enabled = $true }
        }
    } catch {}

    # ServerManager fallback (Windows Server roles/features)
    try {
        $role = Get-WindowsFeature -Name 'Web-Server' -ErrorAction SilentlyContinue
        if ($role -and $role.Installed) {
            return @{ Enabled = $true }
        }
    } catch {}

    return @{ Enabled = $false }
}

function Test-AspNetCoreInstalled {
    param([string]$MajorVersion)

    try {
        $runtimes = & dotnet --list-runtimes 2>$null
        if ($runtimes) {
            $hosting = $runtimes | Where-Object { $_ -match "Microsoft\.AspNetCore\.App $MajorVersion\." }
            if ($hosting) {
                return @{ Installed = $true; Detail = ($hosting | Select-Object -First 1).Trim() }
            }
        }
    } catch {}

    # Also check the hosting bundle via registry
    try {
        $regKeys = Get-ChildItem 'HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedhost' -ErrorAction SilentlyContinue
        if ($regKeys) {
            $match = $regKeys | Where-Object { $_.PSChildName -match "^$MajorVersion\." }
            if ($match) {
                return @{ Installed = $true; Detail = "Hosting bundle $MajorVersion.x (from registry)" }
            }
        }
    } catch {}

    return @{ Installed = $false; Detail = '' }
}

function Test-DiskSpace {
    param([string]$DriveLetter = 'C', [long]$RequiredGB = 10)
    $drive = Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue
    if ($drive) {
        $freeGB = [math]::Round($drive.Free / 1GB, 1)
        return @{
            FreeGB     = $freeGB
            Sufficient = $freeGB -ge $RequiredGB
        }
    }
    return @{ FreeGB = 0; Sufficient = $false }
}

function Invoke-PreflightChecks {
    param([string]$TargetDrive = 'C')

    $results = @{
        IsAdmin  = Test-Administrator
        Sql      = Test-SqlServerInstalled
        IIS      = Test-IISEnabled
        Disk     = Test-DiskSpace -DriveLetter $TargetDrive
    }
    return $results
}

function Test-ArasSiteHealth {
    param([string]$Url)

    $result = @{ Healthy = $false; StatusCode = 0; Error = '' }

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $result.StatusCode = $response.StatusCode
        # Any non-5xx response means the app is running
        if ($response.StatusCode -lt 500) {
            $result.Healthy = $true
        }
    } catch {
        $errMsg = $_.ToString()
        if ($errMsg -match '\((\d{3})\)') {
            $code = [int]$Matches[1]
            $result.StatusCode = $code
            if ($code -lt 500) {
                $result.Healthy = $true
            }
        }
        $result.Error = $errMsg
    }

    return $result
}

Export-ModuleMember -Function Test-Administrator, Test-SqlServerInstalled, Test-IISEnabled,
    Test-AspNetCoreInstalled, Test-DiskSpace, Invoke-PreflightChecks, Test-ArasSiteHealth
