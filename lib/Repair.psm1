function Find-ExistingArasInstall {
    $candidates = @()

    # Check IIS web applications for Aras sites
    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        $webApps = Get-WebApplication -ErrorAction SilentlyContinue
        if ($webApps) {
            foreach ($app in $webApps) {
                $physPath = $app.PhysicalPath
                if ($physPath -and (Test-Path $physPath)) {
                    # Walk up from the web app path to find InnovatorServerConfig.xml
                    $dir = $physPath
                    for ($i = 0; $i -lt 4; $i++) {
                        $cfgPath = Join-Path $dir 'InnovatorServerConfig.xml'
                        if (Test-Path $cfgPath) {
                            $alias = $app.path.TrimStart('/')
                            $candidates += @{ InstallDir = $dir; WebAlias = $alias; ConfigPath = $cfgPath }
                            break
                        }
                        $dir = Split-Path $dir -Parent
                        if (-not $dir) { break }
                    }
                }
            }
        }
    } catch {}

    # Check common install paths (both 64-bit and 32-bit Program Files)
    $commonPaths = @(
        'C:\Program Files\Aras\Innovator',
        'C:\Program Files (x86)\Aras\Innovator',
        'C:\Program Files\Aras Innovator',
        'C:\Program Files (x86)\Aras Innovator',
        'C:\Innovator',
        'C:\Aras\Innovator'
    )
    foreach ($p in $commonPaths) {
        $cfgPath = Join-Path $p 'InnovatorServerConfig.xml'
        if ((Test-Path $cfgPath) -and -not ($candidates | Where-Object { $_.ConfigPath -eq $cfgPath })) {
            $candidates += @{ InstallDir = $p; WebAlias = ''; ConfigPath = $cfgPath }
        }
    }

    if ($candidates.Count -eq 0) { return $null }

    # Return the first (best) match
    return $candidates[0]
}

function Read-InnovatorConfig {
    param([string]$ConfigPath)

    if (-not (Test-Path $ConfigPath)) {
        return @{ Error = "Config file not found: $ConfigPath" }
    }

    $result = @{
        ConfigPath    = $ConfigPath
        DbName        = ''
        DbServer      = ''
        DboUser       = ''
        DboPassword   = ''
        RegularUser   = ''
        RegularPwd    = ''
        LicenseKey    = ''
        ActivationKey = ''
        AgentPort     = 8734
        VaultPath     = ''
        InstallDir    = ''
        WebAlias      = ''
    }

    try {
        $content = Get-Content $ConfigPath -Raw -ErrorAction Stop
        [xml]$xml = $content

        # DB-Connection
        $dbConn = $xml.Innovator.'DB-Connection'
        if ($dbConn) {
            $result.DbName      = $dbConn.database
            $result.DbServer    = $dbConn.server
            $result.DboUser     = $dbConn.dbo_uid
            $result.DboPassword = $dbConn.dbo_pwd
            $result.RegularUser = $dbConn.regular_uid
            $result.RegularPwd  = $dbConn.regular_pwd
        }

        # License
        $license = $xml.Innovator.License
        if ($license) {
            $lk = $license.lic_key
            $ak = $license.act_key
            if ($lk -and $lk -notmatch 'ENTER' -and $lk -notmatch '<!--' -and $lk.Trim() -ne '') {
                $result.LicenseKey = $lk
            }
            if ($ak -and $ak -notmatch 'ENTER' -and $ak -notmatch '<!--' -and $ak.Trim() -ne '') {
                $result.ActivationKey = $ak
            }
        }

        # Agent port from AgentService URL
        $agent = $xml.Innovator.AgentService
        if ($agent) {
            $agentUrl = $agent.InnovatorToServiceAddress
            if ($agentUrl -match ':(\d{4,5})/') {
                $result.AgentPort = [int]$Matches[1]
            }
        }

        # Operating parameters for paths
        $params = $xml.Innovator.operating_parameter
        if ($params) {
            foreach ($p in $params) {
                if ($p.key -eq 'temp_folder' -and $p.value) {
                    # temp_folder is typically <InstallDir>\Innovator\Server\temp\
                    $tempDir = $p.value.TrimEnd('\')
                    $installGuess = $tempDir -replace '\\Innovator\\Server\\temp$', ''
                    if (Test-Path $installGuess) {
                        $result.InstallDir = $installGuess
                    }
                }
            }
        }

        # Vault path -- check for Vault operating_parameter or VAULTFOLDER
        if ($params) {
            foreach ($p in $params) {
                if ($p.key -eq 'Vault' -and $p.value) {
                    $result.VaultPath = $p.value
                }
            }
        }

        # If InstallDir not found from temp_folder, derive from ConfigPath
        if (-not $result.InstallDir) {
            $result.InstallDir = Split-Path $ConfigPath -Parent
        }

    } catch {
        $result.Error = "Failed to parse config: $_"
    }

    return $result
}

function Get-NetworkMacAddresses {
    $adapters = @()
    try {
        $netAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object Name, MacAddress, InterfaceDescription
        foreach ($a in $netAdapters) {
            $adapters += @{
                Name        = $a.Name
                MacAddress  = $a.MacAddress
                Description = $a.InterfaceDescription
            }
        }
    } catch {
        # Get-NetAdapter may not be available on older systems
        try {
            $wmi = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
            foreach ($a in $wmi) {
                $adapters += @{
                    Name        = $a.Description
                    MacAddress  = $a.MACAddress
                    Description = $a.Description
                }
            }
        } catch {}
    }
    return $adapters
}

Export-ModuleMember -Function Find-ExistingArasInstall, Read-InnovatorConfig, Get-NetworkMacAddresses
