#Requires -Version 5.1
<#
.SYNOPSIS
    Kopiert Config-Dateien vom Haupt-Worktree in den aktuellen Worktree.

.DESCRIPTION
    Sucht im Quell-Worktree nach bekannten Config-Dateien und kopiert diese unter
    Beibehaltung der relativen Ordnerstruktur in den aktuellen Worktree.

    Standardmässig werden folgende Patterns berücksichtigt:
      - **/Properties/launchSettings.json
      - **/appsettings.json
      - **/appsettings.*.json
      - **/.env
      - **/.env.*

    Existiert eine Zieldatei bereits, wird per Nachfrage entschieden (ausser bei -Force).

.PARAMETER Force
    Existierende Dateien ohne Nachfrage überschreiben.

.PARAMETER Include
    Zusätzliche Glob-Patterns, ergänzend zu den hardcodierten Defaults.
    Beispiel: -Include '**/custom.json', '**/*.config'

.PARAMETER SourcePath
    Optionaler Pfad zum Quell-Worktree. Wird dieser Parameter weggelassen, ermittelt
    das Script den Haupt-Worktree automatisch via 'git worktree list'.

.EXAMPLE
    .\copy-worktree-config.ps1
    Kopiert Config-Dateien vom Haupt-Worktree (Nachfrage bei bestehenden Dateien).

.EXAMPLE
    .\copy-worktree-config.ps1 -WhatIf
    Zeigt, welche Dateien kopiert würden, ohne etwas zu ändern.

.EXAMPLE
    .\copy-worktree-config.ps1 -Force
    Überschreibt alle bestehenden Dateien ohne Nachfrage.

.EXAMPLE
    .\copy-worktree-config.ps1 -Include '**/custom.json', '**/*.config'
    Kopiert zusätzlich Dateien, die den angegebenen Patterns entsprechen.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Force,

    [string[]]$Include = @(),

    [string]$SourcePath,

    # Interner Parameter für Tests: überschreibt den via Git ermittelten Zielpfad.
    [string]$TargetPath
)

$ErrorActionPreference = 'Stop'

$script:DefaultPatterns = @(
    '**/Properties/launchSettings.json'
    '**/appsettings.json'
    '**/appsettings.*.json'
    '**/.env'
    '**/.env.*'
)

function Get-MainWorktreePath {
    $output = & git worktree list --porcelain 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git worktree list fehlgeschlagen: $output"
    }
    $firstLine = $output | Where-Object { $_ -match '^worktree ' } | Select-Object -First 1
    if (-not $firstLine) {
        throw "Kein Worktree-Eintrag in der Ausgabe von 'git worktree list' gefunden."
    }
    return ($firstLine -replace '^worktree ', '').Trim()
}

function Get-CurrentWorktreeRoot {
    $result = & git rev-parse --show-toplevel 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Nicht in einem Git-Repository: $result"
    }
    return $result.Trim()
}

function Get-FilesMatchingGlob {
    <#
    .SYNOPSIS
        Gibt alle Dateien unter $BasePath zurück, die dem Glob-Pattern entsprechen.
    .DESCRIPTION
        Unterstützt Patterns der Form **/dir/filename oder **/filename.
        Das ** steht für eine beliebig tiefe Verzeichnisstruktur.
    #>
    param(
        [string]$BasePath,
        [string]$Pattern
    )

    [string[]]$segments = $Pattern.Replace('\', '/') -split '/'

    $doubleStarIdx = [Array]::IndexOf($segments, '**')
    [string[]]$suffixSegments = if ($doubleStarIdx -ge 0 -and $doubleStarIdx -lt $segments.Count - 1) {
        $segments[($doubleStarIdx + 1)..($segments.Count - 1)]
    } else {
        $segments
    }

    $fileNamePattern   = $suffixSegments[-1]
    [string[]]$requiredAncestors = if ($suffixSegments.Count -gt 1) {
        $suffixSegments[0..($suffixSegments.Count - 2)]
    } else {
        @()
    }

    Get-ChildItem -Path $BasePath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like $fileNamePattern } |
        Where-Object {
            if ($requiredAncestors.Count -eq 0) { return $true }

            $relDir = $_.DirectoryName.Substring($BasePath.Length).TrimStart('\').Replace('\', '/')
            [string[]]$dirParts = if ([string]::IsNullOrEmpty($relDir)) { @() } else { $relDir -split '/' }

            if ($dirParts.Count -lt $requiredAncestors.Count) { return $false }

            [string[]]$tail = $dirParts[($dirParts.Count - $requiredAncestors.Count)..($dirParts.Count - 1)]
            for ($i = 0; $i -lt $requiredAncestors.Count; $i++) {
                if ($tail[$i] -notlike $requiredAncestors[$i]) { return $false }
            }
            return $true
        }
}

# ---------------------------------------------------------------------------
# Quell- und Zielpfad auflösen
# ---------------------------------------------------------------------------

if ($TargetPath) {
    $resolvedTarget = (Resolve-Path -LiteralPath $TargetPath).Path
} else {
    $resolvedTarget = (Get-CurrentWorktreeRoot).Replace('/', '\')
}
$resolvedTarget = $resolvedTarget.TrimEnd('\')

if ($SourcePath) {
    $resolvedSource = (Resolve-Path -LiteralPath $SourcePath).Path.TrimEnd('\')
} else {
    $resolvedSource = (Get-MainWorktreePath).Replace('/', '\').TrimEnd('\')
}

if ([string]::Equals($resolvedSource, $resolvedTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Error "Quell- und Zielpfad sind identisch ('$resolvedSource'). Das Script muss innerhalb eines verlinkten Worktrees ausgeführt werden, nicht im Hauptcheckout."
    exit 1
}

# ---------------------------------------------------------------------------
# Passende Dateien suchen (Duplikate ausschliessen)
# ---------------------------------------------------------------------------

$allPatterns = $script:DefaultPatterns + $Include
$seenPaths   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$sourceFiles  = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

foreach ($pattern in $allPatterns) {
    foreach ($file in (Get-FilesMatchingGlob -BasePath $resolvedSource -Pattern $pattern)) {
        if ($seenPaths.Add($file.FullName)) {
            $sourceFiles.Add($file)
        }
    }
}

if ($sourceFiles.Count -eq 0) {
    Write-Host "Keine passenden Config-Dateien in '$resolvedSource' gefunden."
    exit 0
}

# ---------------------------------------------------------------------------
# Dateien kopieren
# ---------------------------------------------------------------------------

$overwriteAll = $false

foreach ($srcFile in $sourceFiles) {
    $relativePath = $srcFile.FullName.Substring($resolvedSource.Length).TrimStart('\')
    $destPath     = Join-Path $resolvedTarget $relativePath

    if (-not $PSCmdlet.ShouldProcess($relativePath, 'Kopieren')) {
        continue
    }

    $destExists = Test-Path -LiteralPath $destPath

    if ($destExists -and -not $Force -and -not $overwriteAll) {
        $choices = @(
            [System.Management.Automation.Host.ChoiceDescription]::new('&Ja',        'Diese Datei überschreiben')
            [System.Management.Automation.Host.ChoiceDescription]::new('&Alle',      'Alle bestehenden Dateien überschreiben')
            [System.Management.Automation.Host.ChoiceDescription]::new('&Nein',      'Diese Datei überspringen')
            [System.Management.Automation.Host.ChoiceDescription]::new('&Abbrechen', 'Script beenden')
        )
        $choice = $Host.UI.PromptForChoice('Datei existiert bereits', $relativePath, $choices, 2)
        switch ($choice) {
            0 { <# Ja – weiter mit Kopieren #> }
            1 { $overwriteAll = $true }
            2 { Write-Verbose "Übersprungen: $relativePath"; continue }
            3 { Write-Host 'Abgebrochen.'; exit 0 }
        }
    }

    $destDir = Split-Path -Parent $destPath
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    Copy-Item -LiteralPath $srcFile.FullName -Destination $destPath -Force
    Write-Host "Kopiert: $relativePath"
}
