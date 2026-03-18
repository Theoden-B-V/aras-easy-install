# SQL Server download URLs (offline media: .exe + .box)
$script:SqlServerVersions = @{
    '2019' = @{
        Label  = 'SQL Server 2019 Developer'
        ExeUrl = 'https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SQLServer2019-DEV-x64-ENU.exe'
        BoxUrl = 'https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SQLServer2019-DEV-x64-ENU.box'
    }
    '2022' = @{
        Label  = 'SQL Server 2022 Developer'
        ExeUrl = 'https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLServer2022-DEV-x64-ENU.exe'
        BoxUrl = 'https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SQLServer2022-DEV-x64-ENU.box'
    }
}

# ASP.NET Core Hosting Bundle download URLs
$script:AspNetCoreBundles = @{
    '6.0' = @{
        Label = 'ASP.NET Core 6.0 Hosting Bundle'
        Url   = 'https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/6.0.6/dotnet-hosting-6.0.6-win.exe'
    }
    '8.0' = @{
        Label = 'ASP.NET Core 8.0 Hosting Bundle'
        Url   = 'https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/8.0.22/dotnet-hosting-8.0.22-win.exe'
    }
}

# IIS features required for Aras Innovator
$script:IISFeatures = @(
    'IIS-WebServerRole',
    'IIS-WebServer',
    'IIS-CommonHttpFeatures',
    'IIS-StaticContent',
    'IIS-DefaultDocument',
    'IIS-DirectoryBrowsing',
    'IIS-HttpErrors',
    'IIS-HttpRedirect',
    'IIS-ApplicationDevelopment',
    'IIS-ASPNET45',
    'IIS-NetFxExtensibility45',
    'IIS-ISAPIExtensions',
    'IIS-ISAPIFilter',
    'IIS-HealthAndDiagnostics',
    'IIS-HttpLogging',
    'IIS-Security',
    'IIS-RequestFiltering',
    'IIS-Performance',
    'IIS-HttpCompressionStatic',
    'IIS-WebServerManagementTools',
    'IIS-ManagementConsole',
    'NetFx4Extended-ASPNET45'
)

# Default configuration values
$script:Defaults = @{
    InstallDir = 'C:\Program Files\Aras\Innovator'
    WebAlias   = 'InnovatorServer'
    VaultPath  = 'C:\Program Files\Aras\Innovator\Vault'
    DbName     = 'InnovatorSolutions'
    AgentPort  = 8734
}

function Get-SqlServerVersions  { return $script:SqlServerVersions }
function Get-AspNetCoreBundles  { return $script:AspNetCoreBundles }
function Get-IISFeatures        { return $script:IISFeatures }
function Get-InstallerDefaults  { return $script:Defaults }

Export-ModuleMember -Function Get-SqlServerVersions, Get-AspNetCoreBundles, Get-IISFeatures, Get-InstallerDefaults
