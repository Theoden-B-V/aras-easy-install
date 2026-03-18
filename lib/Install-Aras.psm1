function Install-AspNetCoreBundle {
    param([string]$Version)  # '6.0', '8.0', or 'none'

    if ($Version -eq 'none') {
        Show-Info 'Skipping ASP.NET Core Hosting Bundle (not selected)'
        return $true
    }

    $bundles = Get-AspNetCoreBundles
    $bundle = $bundles[$Version]
    if (-not $bundle) { throw "Unknown ASP.NET Core version: $Version" }

    # Check if already installed
    $check = Test-AspNetCoreInstalled -MajorVersion $Version
    if ($check.Installed) {
        Show-Info "ASP.NET Core $Version already installed: $($check.Detail)"
        return $true
    }

    $tempFile = Join-Path $env:TEMP "dotnet-hosting-$Version.exe"
    Start-Download -Url $bundle.Url -OutFile $tempFile -Label $bundle.Label

    Show-Info "Installing $($bundle.Label)..."
    $proc = Start-Process -FilePath $tempFile `
        -ArgumentList '/install', '/quiet', '/norestart' `
        -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        throw "$($bundle.Label) install failed with exit code $($proc.ExitCode)"
    }

    try { Remove-Item $tempFile -Force } catch {}

    Show-Info 'Restarting IIS to load the ASP.NET Core module...'
    & iisreset /restart 2>&1 | Out-Null
    Show-Success "$($bundle.Label) installed"
    return $true
}

function Install-ArasInnovator {
    param(
        [hashtable]$Config  # Full configuration hashtable from wizard
    )

    $msiPath    = $Config.MsiPath
    $installDir = $Config.InstallDir
    $webAlias   = $Config.WebAlias
    $vaultPath  = $Config.VaultPath
    $dbName     = $Config.DbName
    $saPassword = $Config.SaPassword
    $agentPort  = $Config.AgentPort

    if (-not (Test-Path $msiPath)) {
        throw "Aras MSI not found at: $msiPath"
    }

    # Remove leftover Aras Agent services from a previous install.
    # The MSI refuses to run if any Aras Agent service is registered.
    $agentServices = Get-Service -Name 'ArasInnovatorAgent*' -ErrorAction SilentlyContinue
    if ($agentServices) {
        foreach ($s in $agentServices) {
            Show-Info "Removing leftover service: $($s.Name)"
            if ($s.Status -eq 'Running') { Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue }
            & sc.exe delete $s.Name 2>&1 | Out-Null
        }
    }

    # Remove leftover IIS web application that would conflict with the new alias
    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        $existing = Get-WebApplication -Name $webAlias -ErrorAction SilentlyContinue
        if ($existing) {
            Show-Info "Removing leftover IIS application: /$webAlias"
            Remove-WebApplication -Name $webAlias -Site 'Default Web Site' -ErrorAction SilentlyContinue
        }
    } catch {}

    # Ensure install and vault directories exist
    if (-not (Test-Path $installDir)) {
        New-Item -Path $installDir -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path $vaultPath)) {
        New-Item -Path $vaultPath -ItemType Directory -Force | Out-Null
    }

    $logFile = Join-Path $env:TEMP 'ArasInnovatorSetup.log'

    # Check if the target database already exists in SQL Server
    $dbMode = '0'  # 0 = create new
    try {
        $sqlCheck = & sqlcmd -S 127.0.0.1 -U sa -P "$saPassword" -Q "SELECT DB_ID('$dbName')" -h -1 -W 2>$null
        if ($sqlCheck -and $sqlCheck.Trim() -ne '' -and $sqlCheck.Trim() -ne 'NULL') {
            Show-Warn "Database '$dbName' already exists in SQL Server."
            Show-Info 'The installer will use the existing database.'
            $dbMode = '1'  # 1 = use existing
        }
    } catch {}

    Show-Info 'Running Aras Innovator MSI installer...'
    Show-Info '(This may take several minutes)'

    $msiArgs = @(
        '/i'
        "`"$msiPath`""
        '/qn'
        '/norestart'
        "/log `"$logFile`""
        "INSTALLDIR=`"$installDir`""
        'UPGRADEORINSTALL=1'
        "WEBALIAS=`"$webAlias`""
        'SMTPSERVER=queue'
        "VAULTNAME=$dbName"
        "VAULTFOLDER=`"$vaultPath`""
        "DB_CREATE_NEW_OR_USE_EXISTING=$dbMode"
        'IS_SQLSERVER_SERVER=127.0.0.1'
        "IS_SQLSERVER_DATABASE=$dbName"
        'IS_SQLSERVER_AUTHENTICATION=1'
        'IS_SQLSERVER_USERNAME=sa'
        "IS_SQLSERVER_PASSWORD=$saPassword"
        'SQL_SERVER_LOGIN_NAME=innovator'
        "SQL_SERVER_LOGIN_PASSWORD=$saPassword"
        'SQL_SERVER_LOGIN_REGULAR_NAME=innovator_regular'
        "SQL_SERVER_LOGIN_REGULAR_PASSWORD=$saPassword"
        'INSTALL_CONVERSION_SERVER=1'
        'CONVERSION_SERVER_NAME=ConversionServer'
        "CONVERSION_SERVER_APP_URL=http://localhost/$webAlias/Server/InnovatorServer.aspx"
        'INSTALL_AGENT_SERVICE=1'
        "ARAS_AGENTSERVICE_TO_INNOVATORSERVER_URL=http://localhost/$webAlias/Server/InnovatorServer.aspx"
        "INNOVATOR_TO_SERVICE_ADDRESS=http://localhost:${agentPort}/ArasInnovatorAgent"
        'AS_FOLDER=ArasInnovatorAgent'
    )

    $argString = $msiArgs -join ' '
    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $argString `
        -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        Show-Error "MSI install log: $logFile"
        throw "Aras Innovator MSI failed with exit code $($proc.ExitCode)"
    }

    Show-Info 'Restarting IIS to apply Aras site configuration...'
    & iisreset /restart 2>&1 | Out-Null
    Show-Success 'Aras Innovator installed'
    return $true
}

function Write-InnovatorServerConfig {
    param([hashtable]$Config)

    $installDir    = $Config.InstallDir
    $vaultPath     = $Config.VaultPath
    $dbName        = $Config.DbName
    $saPassword    = $Config.SaPassword
    $agentPort     = $Config.AgentPort
    $webAlias      = $Config.WebAlias
    $licenseKey    = $Config.LicenseKey
    $activationKey = $Config.ActivationKey

    $licKeyAttr = if ($licenseKey)    { $licenseKey }    else { '' }
    $actKeyAttr = if ($activationKey) { $activationKey } else { '' }

    $xmlContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<Innovator>
    <UI-Tailoring login_splash="../images/aras-innovator.svg" branding_img="../images/aras-innovator.svg" product_name="Aras Innovator" banner_url="../scripts/banner.aspx" banner_height="50"/>
    <operating_parameter key="debug_log_flag" value="false"/>
    <operating_parameter key="debug_log_limit" value="10000"/>
    <operating_parameter key="debug_log_pretty" value="true"/>
    <operating_parameter key="xslt_processor_debug" value="false"/>
    <License lic_type="Unlimited" lic_key="$licKeyAttr" act_key="$actKeyAttr" company=""/>
    <Mail SMTPServer="queue"/>
    <operating_parameter key="temp_folder" value="$installDir\Innovator\Server\temp\"/>
    <operating_parameter key="ServerMethodTempDir" value="$installDir\Innovator\Server\dll\"/>
    <operating_parameter key="debug_log_prefix" value="$installDir\Innovator\Server\logs\"/>
    <AgentService InnovatorToServiceAddress="http://localhost:$agentPort/ArasInnovatorAgent"/>
    <OAuthServerDiscovery>
        <Urls>
            <Url value="`$[HTTP_PREFIX_SERVER]`$[HTTP_HOST_SERVER]`$[HTTP_PORT_SERVER]`$[HTTP_PATH_SERVER]/OAuthServer/"/>
        </Urls>
    </OAuthServerDiscovery>
    <DB-Connection id="$dbName" database="$dbName" server="localhost" regular_uid="innovator_regular" regular_pwd="$saPassword" dbo_uid="innovator" dbo_pwd="$saPassword"/>
</Innovator>
"@

    $configPath = Join-Path $installDir 'InnovatorServerConfig.xml'
    $xmlContent | Out-File -FilePath $configPath -Encoding UTF8 -Force
    Show-Success "Written InnovatorServerConfig.xml to $configPath"

    if (-not $licenseKey) {
        Show-Warn 'License key not set. Edit InnovatorServerConfig.xml before using Aras.'
        Show-Info  'Request a key at: https://www.aras.com/en/support/licensekeyservice'
    }

    return $configPath
}

Export-ModuleMember -Function Install-AspNetCoreBundle, Install-ArasInnovator, Write-InnovatorServerConfig
