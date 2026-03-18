function Find-ArasMsiFiles {
    param([string]$CdImagePath)

    $resolved = Resolve-Path -Path $CdImagePath -ErrorAction SilentlyContinue
    if (-not $resolved) {
        return @{ Error = "Path does not exist: $CdImagePath" }
    }

    $fullPath = $resolved.Path
    if (-not (Test-Path $fullPath -PathType Container)) {
        return @{ Error = "Path is not a folder: $fullPath" }
    }

    $msiFiles = Get-ChildItem -Path $fullPath -Recurse -Filter '*.msi' -File -Depth 3 -ErrorAction SilentlyContinue |
        ForEach-Object {
            @{
                Name = $_.Name
                Path = $_.FullName
                Size = $_.Length
                Dir  = $_.DirectoryName
            }
        }

    if (-not $msiFiles -or $msiFiles.Count -eq 0) {
        return @{ Error = "No .msi files found under: $fullPath" }
    }

    # Ensure it's always an array
    if ($msiFiles -isnot [array]) { $msiFiles = @($msiFiles) }

    $recommended = $msiFiles | Where-Object {
        $_.Name -match 'innovator' -or $_.Name -match 'InnovatorSetup'
    } | Select-Object -First 1

    if (-not $recommended) { $recommended = $msiFiles[0] }

    $version = Find-ArasVersion -CdImagePath $fullPath -MsiFiles $msiFiles

    return @{
        Path            = $fullPath
        MsiFiles        = $msiFiles
        Recommended     = $recommended
        DetectedVersion = $version
    }
}

function Find-ArasVersion {
    param([string]$CdImagePath, [array]$MsiFiles)

    $targets = @((Split-Path $CdImagePath -Leaf))
    foreach ($m in $MsiFiles) {
        $targets += $m.Name
        $targets += (Split-Path $m.Dir -Leaf)
    }
    $combined = $targets -join ' '

    if ($combined -match '(20[1-9]\d)') {
        return "Release $($Matches[1])"
    }
    if ($combined -match '(\d{1,2}\.\d+(?:\.\d+)?)') {
        return $Matches[1]
    }
    return $null
}

function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}

Export-ModuleMember -Function Find-ArasMsiFiles, Format-FileSize
