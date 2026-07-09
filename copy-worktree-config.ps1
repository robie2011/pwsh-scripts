#Requires -Version 5.1
<#
.SYNOPSIS
    Copies config files from the main worktree into the current worktree.

.DESCRIPTION
    Searches the source worktree for known config files and copies them into the
    current worktree, preserving the relative directory structure.

    The following patterns are matched by default:
      - **/Properties/launchSettings.json
      - **/appsettings.json
      - **/appsettings.*.json
      - **/.env
      - **/.env.*

    If a target file already exists, the user is prompted (unless -Force is set).

.PARAMETER Force
    Overwrite existing files without prompting.

.PARAMETER Include
    Additional glob patterns on top of the built-in defaults.
    Example: -Include '**/custom.json', '**/*.config'

.PARAMETER SourcePath
    Optional path to the source worktree. When omitted, the main worktree is
    detected automatically via 'git worktree list'.

.EXAMPLE
    .\copy-worktree-config.ps1
    Copies config files from the main worktree (prompts before overwriting).

.EXAMPLE
    .\copy-worktree-config.ps1 -WhatIf
    Shows which files would be copied without making any changes.

.EXAMPLE
    .\copy-worktree-config.ps1 -Force
    Overwrites all existing files without prompting.

.EXAMPLE
    .\copy-worktree-config.ps1 -Include '**/custom.json', '**/*.config'
    Also copies files matching the given patterns.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Force,

    [string[]]$Include = @(),

    [string]$SourcePath,

    # Internal parameter for tests: overrides the Git-detected target path.
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
        throw "git worktree list failed: $output"
    }
    $firstLine = $output | Where-Object { $_ -match '^worktree ' } | Select-Object -First 1
    if (-not $firstLine) {
        throw "No worktree entry found in output of 'git worktree list'."
    }
    return ($firstLine -replace '^worktree ', '').Trim()
}

function Get-CurrentWorktreeRoot {
    $result = & git rev-parse --show-toplevel 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Not in a Git repository: $result"
    }
    return $result.Trim()
}

function Get-FilesMatchingGlob {
    <#
    .SYNOPSIS
        Returns all files under $BasePath that match the given glob pattern.
    .DESCRIPTION
        Supports patterns of the form **/dir/filename or **/filename.
        The ** matches any directory depth.
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
# Resolve source and target paths
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
    Write-Error "Source and target paths are identical ('$resolvedSource'). The script must be run from within a linked worktree, not the main checkout."
    exit 1
}

# ---------------------------------------------------------------------------
# Collect matching files (skip duplicates)
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
    Write-Host "No matching config files found in '$resolvedSource'."
    exit 0
}

# ---------------------------------------------------------------------------
# Copy files
# ---------------------------------------------------------------------------

$overwriteAll = $false

foreach ($srcFile in $sourceFiles) {
    $relativePath = $srcFile.FullName.Substring($resolvedSource.Length).TrimStart('\')
    $destPath     = Join-Path $resolvedTarget $relativePath

    if (-not $PSCmdlet.ShouldProcess($relativePath, 'Copy')) {
        continue
    }

    $destExists = Test-Path -LiteralPath $destPath

    if ($destExists -and -not $Force -and -not $overwriteAll) {
        $choices = @(
            [System.Management.Automation.Host.ChoiceDescription]::new('&Yes',    'Overwrite this file')
            [System.Management.Automation.Host.ChoiceDescription]::new('&All',    'Overwrite all existing files')
            [System.Management.Automation.Host.ChoiceDescription]::new('&No',     'Skip this file')
            [System.Management.Automation.Host.ChoiceDescription]::new('&Cancel', 'Stop the script')
        )
        $choice = $Host.UI.PromptForChoice('File already exists', $relativePath, $choices, 2)
        switch ($choice) {
            0 { <# Yes – continue with copy #> }
            1 { $overwriteAll = $true }
            2 { Write-Verbose "Skipped: $relativePath"; continue }
            3 { Write-Host 'Cancelled.'; exit 0 }
        }
    }

    $destDir = Split-Path -Parent $destPath
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    Copy-Item -LiteralPath $srcFile.FullName -Destination $destPath -Force
    Write-Host "Copied: $relativePath"
}
