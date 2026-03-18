# aras-easy-install

One-script installer for Aras Innovator on Windows. Handles SQL Server, IIS,
ASP.NET Core, the Aras MSI, and config generation. You answer a few questions,
it does the rest.

## Before you start

**Get the Aras Innovator CD Image.** You need the extracted installer folder
that contains the `.msi` file.

- **Community Edition (free):** register at
  [aras.com/innovator](https://aras.com/innovator), download the CD Image zip,
  and extract it.
- **Licensed customers:** download from your Aras MFT (Managed File Transfer)
  portal.

**System requirements:**

- Windows 10, 11, or Server 2016+
- PowerShell 5.1 (ships with Windows)
- Administrator privileges
- ~10 GB free disk space

## Run it

Double-click the launcher -- it self-elevates to admin and bypasses execution
policy automatically:

```
Install-Aras.cmd
```

Or run it yourself from an admin PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-Aras.ps1
```

## What it does

The wizard walks you through 7 steps:

1. **Aras CD Image** -- point it at your extracted folder. It finds the MSI and
   detects the version automatically.
2. **SQL Server** -- installs 2019 or 2022 Developer Edition, or reuses an
   existing instance.
3. **ASP.NET Core** -- installs the 6.0 or 8.0 Hosting Bundle (required by
   newer Aras versions for OAuth). Skippable for older releases.
4. **Aras config** -- install directory, IIS web alias, vault path.
5. **Licensing** -- enter your license and activation keys now, or skip and add
   them later.
6. **Review** -- see every setting before anything touches your system.
7. **Install** -- enables IIS features, installs SQL Server, runs the Aras MSI,
   writes `InnovatorServerConfig.xml`, generates an uninstall script.

After install it runs a health check against `http://localhost/<alias>` and
tells you whether the site came up.

## Repair mode

Run the script again on a machine that already has Aras installed. It finds the
existing config, reads database/license/network details, and diagnoses each
component (IIS, SQL, ASP.NET Core, site health). If anything is broken it offers
to fix it. You can also update the license key without editing XML by hand.

## Uninstall

The installer generates `Uninstall-Aras.ps1` in your Aras install directory.

```powershell
.\Uninstall-Aras.ps1                              # remove Aras only
.\Uninstall-Aras.ps1 -RemoveSqlServer -RemoveIIS  # full cleanup
```

## File layout

```
aras-easy-install/
  Install-Aras.cmd          Launcher (admin + execution policy bypass)
  Install-Aras.ps1          Main wizard script
  lib/
    Constants.psm1           Download URLs, feature lists, defaults
    UI.psm1                  Interactive prompts and menus
    Scanner.psm1             CD Image scanning and version detection
    Preflight.psm1           Pre-install checks (admin, disk, IIS, SQL)
    Install-IIS.psm1         IIS feature enablement
    Install-SQL.psm1         SQL Server silent install
    Install-Aras.psm1        Aras MSI runner + config writer
    Repair.psm1              Existing install detection and repair
    Uninstaller.psm1         Uninstall script generator
```

## Compatibility

- **Windows:** 10 / 11 / Server 2016+
- **PowerShell:** 5.1 (built into Windows -- no newer version needed)
- **Aras Innovator:** any version that ships an MSI installer
- **SQL Server:** 2019 or 2022 Developer Edition (auto-downloaded)
- **ASP.NET Core:** 6.0 for Aras 2023/2024, 8.0 for Aras 2025+

## License

MIT -- see [LICENSE](LICENSE).
