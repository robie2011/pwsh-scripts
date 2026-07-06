#Requires -Version 5.1
<#
.SYNOPSIS
    Save and run CLI command snippets by id or name.

.DESCRIPTION
    Snippets are stored in $env:APPDATA\snippets\snippets.json

.EXAMPLE
    snippets
    List all snippets.

.EXAMPLE
    snippets docker build
    Search snippets matching all keywords.

.EXAMPLE
    snippets -Add
    Add a snippet via notepad JSON template.

.EXAMPLE
    snippets -Add -Interactive
    Add a snippet via interactive prompts.

.EXAMPLE
    snippets -Run 1
    Run snippet id 1.

.EXAMPLE
    snippets -ChangeDirectory build
    Change to the working directory of snippet "build".

.EXAMPLE
    snippets -Remove -Id 1
    Remove snippet id 1.

.EXAMPLE
    snippets -ClearAll
    Remove all snippets.

.EXAMPLE
    snippets -Info
    Print the snippets.json file path in use.

.NOTES
    Add to your profile so run/cd changes your shell directory:
    function snippets { . 'C:\path\to\snippets.ps1' @args }
#>
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Keywords,

    [switch]$Add,
    [switch]$Interactive,
    [switch]$ChangeDirectory,
    [switch]$Run,
    [switch]$Remove,
    [int]$Id = -1,
    [string]$Name,
    [switch]$ClearAll,
    [switch]$Info,
    [string]$Config
)

$ErrorActionPreference = 'Stop'

function Resolve-SnippetsFilePath {
    param([string]$CustomPath)
    if ([string]::IsNullOrWhiteSpace($CustomPath)) {
        return Join-Path (Join-Path $env:APPDATA 'snippets') 'snippets.json'
    }
    if ([System.IO.Path]::IsPathRooted($CustomPath)) {
        return $CustomPath
    }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $CustomPath))
}

$SnippetsFile = Resolve-SnippetsFilePath $Config
$SnippetsDir = Split-Path -Parent $SnippetsFile

function Get-SnippetStore {
    if (-not (Test-Path -LiteralPath $SnippetsFile)) {
        return [pscustomobject]@{
            nextId   = 1
            snippets = @()
        }
    }
    $raw = Get-Content -LiteralPath $SnippetsFile -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{
            nextId   = 1
            snippets = @()
        }
    }
    return $raw | ConvertFrom-Json
}

function Save-SnippetStore {
    param($Store)
    if (-not (Test-Path -LiteralPath $SnippetsDir)) {
        New-Item -ItemType Directory -Path $SnippetsDir -Force | Out-Null
    }
    $Store | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $SnippetsFile -Encoding UTF8
}

function Get-SnippetList {
    param($Store)
    if ($null -eq $Store.snippets) {
        return @()
    }
    @($Store.snippets)
}

function Show-Snippets {
    param($Store)
    $list = Get-SnippetList $Store
    if ($list.Count -eq 0) {
        Write-Host 'No snippets.'
        return
    }
    $list | Sort-Object { [int]$_.id } | ForEach-Object {
        $desc = if ($null -eq $_.description) { '' } else { $_.description }
        Write-Host ("{0,3}  {1,-20}  {2}" -f $_.id, $_.name, $desc)
    }
}

function Show-SnippetDetail {
    param($Snippet)
    Write-Host "id: $($Snippet.id)"
    Write-Host "name: $($Snippet.name)"
    $desc = if ($null -eq $Snippet.description) { '' } else { $Snippet.description }
    Write-Host "description: $desc"
    Write-Host "command: $($Snippet.command)"
    $wd = if ($null -eq $Snippet.workingDirectory) { '' } else { $Snippet.workingDirectory }
    Write-Host "working-directory: $wd"
}

function Get-SnippetSearchText {
    param($Snippet)
    $parts = @(
        $Snippet.name
        $Snippet.description
        $Snippet.command
        $Snippet.workingDirectory
    )
    ($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
}

function Find-SnippetsByKeywords {
    param(
        $Store,
        [string[]]$Terms
    )
    $list = Get-SnippetList $Store
    $list | Where-Object {
        $haystack = Get-SnippetSearchText $_
        $allMatch = $true
        foreach ($term in $Terms) {
            if ($haystack -notmatch [regex]::Escape($term)) {
                $allMatch = $false
                break
            }
        }
        $allMatch
    }
}

function Get-SnippetByTarget {
    param(
        $Store,
        [string]$Target
    )
    if ([string]::IsNullOrWhiteSpace($Target)) {
        return $null
    }
    $list = Get-SnippetList $Store
    if ($Target -match '^\d+$') {
        return $list | Where-Object { [int]$_.id -eq [int]$Target } | Select-Object -First 1
    }
    return $list | Where-Object { $_.name -eq $Target } | Select-Object -First 1
}

function Resolve-SnippetWorkingDirectory {
    param([string]$WorkingDirectory)
    if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        return $null
    }
    if (-not (Test-Path -LiteralPath $WorkingDirectory)) {
        throw "Working directory does not exist: $WorkingDirectory"
    }
    (Resolve-Path -LiteralPath $WorkingDirectory).Path
}

function Set-SnippetLocation {
    param($Snippet)
    $dest = Resolve-SnippetWorkingDirectory $Snippet.workingDirectory
    if ($null -eq $dest) {
        throw "Snippet has no working directory: $($Snippet.name)"
    }
    Set-Location -LiteralPath $dest
    Write-Host "-> $dest"
}

function Expand-SnippetCommand {
    param([string]$Command)
    $expanded = $Command
    $matches = [regex]::Matches($Command, '\$\$([^$]+)\$\$')
    $seen = @{}
    foreach ($match in $matches) {
        $varName = $match.Groups[1].Value
        if ($seen.ContainsKey($varName)) {
            continue
        }
        $seen[$varName] = $true
        $value = Read-Host "Enter value for $varName"
        $placeholder = "`$`$$varName`$`$"
        $expanded = $expanded.Replace($placeholder, $value)
    }
    $expanded
}

function New-SnippetInputFromObject {
    param($InputObject)
    $name = [string]$InputObject.name
    $command = [string]$InputObject.command
    $description = [string]$InputObject.description
    $workingDirectory = [string]$InputObject.workingDirectory

    if ([string]::IsNullOrWhiteSpace($name)) {
        throw 'Snippet name is required.'
    }
    if ([string]::IsNullOrWhiteSpace($command)) {
        throw 'Snippet command is required.'
    }

    $resolvedWd = $null
    if (-not [string]::IsNullOrWhiteSpace($workingDirectory)) {
        $resolvedWd = Resolve-SnippetWorkingDirectory $workingDirectory
    }

    [pscustomobject]@{
        name             = $name.Trim()
        description      = if ([string]::IsNullOrWhiteSpace($description)) { '' } else { $description.Trim() }
        command          = $command.Trim()
        workingDirectory = $resolvedWd
    }
}

function Add-SnippetFromObject {
    param(
        $Store,
        $InputObject
    )
    $snippetInput = New-SnippetInputFromObject $InputObject
    $list = @(Get-SnippetList $Store)
    if ($list | Where-Object { $_.name -eq $snippetInput.name }) {
        throw "Snippet name already exists: $($snippetInput.name)"
    }

    $newId = [int]$Store.nextId
    $entry = [pscustomobject]@{
        id               = $newId
        name             = $snippetInput.name
        description      = $snippetInput.description
        command          = $snippetInput.command
        workingDirectory = $snippetInput.workingDirectory
    }
    $list += $entry
    $Store.snippets = $list
    $Store.nextId = $newId + 1
    Save-SnippetStore $Store
    Write-Host "Added snippet $newId ($($snippetInput.name))"
    $entry
}

function Get-SnippetAddTemplate {
    @'
{
  "name": "",
  "description": "",
  "command": "",
  "workingDirectory": ""
}
'@
}

function Invoke-SnippetAddFromNotepad {
    param($Store)
    $tempFile = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.json')
    try {
        Get-SnippetAddTemplate | Set-Content -LiteralPath $tempFile -Encoding UTF8
        $editor = Start-Process -FilePath 'notepad.exe' -ArgumentList $tempFile -PassThru
        $editor.WaitForExit()
        $raw = Get-Content -LiteralPath $tempFile -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            throw 'No snippet content was saved.'
        }
        try {
            $parsed = $raw | ConvertFrom-Json
        }
        catch {
            throw 'Invalid JSON in snippet template.'
        }
        Add-SnippetFromObject -Store $Store -InputObject $parsed
    }
    finally {
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force
        }
    }
}

function Invoke-SnippetAddInteractive {
    param($Store)
    $name = Read-Host 'name'
    $description = Read-Host 'description (optional)'
    $command = Read-Host 'command'
    $workingDirectory = Read-Host 'workingDirectory (optional)'
    $inputObject = [pscustomobject]@{
        name             = $name
        description      = $description
        command          = $command
        workingDirectory = $workingDirectory
    }
    Add-SnippetFromObject -Store $Store -InputObject $inputObject
}

function Get-SearchKeywords {
    param([string[]]$Terms)
    if ($null -eq $Terms -or $Terms.Count -eq 0) {
        return @()
    }
    if ($Terms[0] -eq 'keyword-search') {
        return @($Terms | Select-Object -Skip 1)
    }
    @($Terms)
}

function Get-ActionTarget {
    param([string[]]$Terms)
    if ($null -eq $Terms -or $Terms.Count -eq 0) {
        throw 'Specify a snippet id or name.'
    }
    if ($Terms.Count -gt 1) {
        throw 'Specify only one snippet id or name.'
    }
    $Terms[0]
}

if ($Info) {
    Write-Output $SnippetsFile
    return
}

if ($ClearAll) {
    $empty = [pscustomobject]@{
        nextId   = 1
        snippets = @()
    }
    Save-SnippetStore $empty
    Write-Host 'All snippets removed.'
    return
}

$store = Get-SnippetStore

if ($Add) {
    if ($Interactive) {
        Invoke-SnippetAddInteractive -Store $store
    }
    else {
        Invoke-SnippetAddFromNotepad -Store $store
    }
    return
}

if ($Remove) {
    $removeById = $PSBoundParameters.ContainsKey('Id')
    if ($removeById -and -not [string]::IsNullOrWhiteSpace($Name)) {
        throw 'Use either -Id or -Name, not both.'
    }
    if (-not $removeById -and [string]::IsNullOrWhiteSpace($Name)) {
        throw 'Use -Id or -Name to specify which snippet to remove.'
    }
    $list = @(Get-SnippetList $store)
    if ($list.Count -eq 0) {
        throw 'No snippets to remove.'
    }
    $match = if ($removeById) {
        $list | Where-Object { [int]$_.id -eq $Id }
    }
    else {
        $list | Where-Object { $_.name -eq $Name }
    }
    if (-not $match) {
        $label = if ($removeById) { "id $Id" } else { "name '$Name'" }
        throw "Snippet not found: $label"
    }
    $removed = @($match)[0]
    $store.snippets = @($list | Where-Object { [int]$_.id -ne [int]$removed.id })
    Save-SnippetStore $store
    Write-Host "Removed snippet $($removed.id) ($($removed.name))"
    return
}

if ($Run) {
    $target = Get-ActionTarget $Keywords
    $snippet = Get-SnippetByTarget $store $target
    if (-not $snippet) {
        throw "Snippet not found: $target"
    }
    if (-not [string]::IsNullOrWhiteSpace($snippet.workingDirectory)) {
        $dest = Resolve-SnippetWorkingDirectory $snippet.workingDirectory
        Set-Location -LiteralPath $dest
        Write-Host "-> $dest"
    }
    $command = Expand-SnippetCommand $snippet.command
    Invoke-Expression $command
    return
}

if ($ChangeDirectory) {
    $target = Get-ActionTarget $Keywords
    $snippet = Get-SnippetByTarget $store $target
    if (-not $snippet) {
        throw "Snippet not found: $target"
    }
    Set-SnippetLocation $snippet
    return
}

$searchTerms = Get-SearchKeywords $Keywords
if ($searchTerms.Count -eq 0) {
    Show-Snippets $store
    return
}

$matches = @(Find-SnippetsByKeywords $store $searchTerms)
if ($matches.Count -eq 0) {
    Write-Host 'No snippets matched.'
    return
}

for ($i = 0; $i -lt $matches.Count; $i++) {
    if ($i -gt 0) {
        Write-Host ''
    }
    Show-SnippetDetail $matches[$i]
}
