function Install-SqlServer {
    param(
        [string]$Version,       # '2019' or '2022'
        [string]$SaPassword,
        [string]$TempDir = "$env:TEMP\ArasSQL"
    )

    # If SQL Server is already installed and running, skip the heavy download/install
    $svc = Get-Service -Name 'MSSQLSERVER' -ErrorAction SilentlyContinue
    if ($svc) {
        Show-Info 'SQL Server instance (MSSQLSERVER) already exists on this machine.'
        if ($svc.Status -ne 'Running') {
            Show-Info 'Starting SQL Server...'
            Set-Service -Name 'MSSQLSERVER' -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name 'MSSQLSERVER' -ErrorAction SilentlyContinue
        }
        Show-Success 'SQL Server is running -- skipping reinstall'
        return $true
    }

    $versions = Get-SqlServerVersions
    $sql = $versions[$Version]
    if (-not $sql) { throw "Unknown SQL Server version: $Version" }

    if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
    New-Item -Path $TempDir -ItemType Directory -Force | Out-Null

    $exeFile = Join-Path $TempDir "SQLServer${Version}-DEV-x64-ENU.exe"
    $boxFile = Join-Path $TempDir "SQLServer${Version}-DEV-x64-ENU.box"
    $extractDir = Join-Path $TempDir 'extracted'

    # Download
    Start-Download -Url $sql.ExeUrl -OutFile $exeFile -Label "$($sql.Label) installer"
    Start-Download -Url $sql.BoxUrl -OutFile $boxFile -Label "$($sql.Label) media"

    # Extract -- the .exe extracts using /qs /x:<path>
    Show-Info 'Extracting SQL Server media...'
    $extractProc = Start-Process -FilePath $exeFile `
        -ArgumentList "/qs /x:`"$extractDir`"" `
        -Wait -PassThru -NoNewWindow
    if ($extractProc.ExitCode -ne 0) {
        throw "SQL Server extraction failed with exit code $($extractProc.ExitCode)"
    }
    Show-Success 'Extraction complete'

    # Install via cmd.exe (SQL Server setup fails when invoked from PowerShell directly)
    Show-Info "Installing $($sql.Label) (this may take 5-15 minutes)..."

    $setupExe = Join-Path $extractDir 'setup.exe'
    $installArgs = @(
        '/Q'
        '/ACTION=Install'
        '/FEATURES=SQLENGINE'
        '/INSTANCENAME=MSSQLSERVER'
        '/SECURITYMODE=SQL'
        "/SAPWD=`"$SaPassword`""
        '/SQLSVCACCOUNT="NT AUTHORITY\System"'
        '/AGTSVCACCOUNT="NT AUTHORITY\System"'
        '/SQLSYSADMINACCOUNTS="BUILTIN\Administrators"'
        '/IACCEPTSQLSERVERLICENSETERMS=1'
        '/TCPENABLED=1'
        '/UPDATEENABLED=False'
    )

    $argString = $installArgs -join ' '
    $proc = Start-Process -FilePath 'cmd.exe' `
        -ArgumentList "/c `"`"$setupExe`" $argString`"" `
        -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        # Check if SQL Server ended up running despite the exit code
        # (e.g. "features already installed" = -2068643838)
        $svcAfter = Get-Service -Name 'MSSQLSERVER' -ErrorAction SilentlyContinue
        if ($svcAfter) {
            Show-Warn "Setup exited with code $($proc.ExitCode) but SQL Server is present."
            Show-Info 'This usually means the instance was already installed. Continuing.'
        } else {
            throw "SQL Server installation failed with exit code $($proc.ExitCode). Check logs at: $extractDir\setup_log"
        }
    }

    # Ensure service starts automatically
    Set-Service -Name 'MSSQLSERVER' -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name 'MSSQLSERVER' -ErrorAction SilentlyContinue

    # Cleanup temp files
    try { Remove-Item $TempDir -Recurse -Force } catch {}

    Show-Success "$($sql.Label) installed and running"
    return $true
}

Export-ModuleMember -Function Install-SqlServer
