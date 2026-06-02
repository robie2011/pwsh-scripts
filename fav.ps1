#Requires -Version 5.1
<#
.SYNOPSIS
    Navigate to filesystem bookmarks by id or alias.

.DESCRIPTION
    Bookmarks are stored in $env:APPDATA\fav\bookmarks.json

.EXAMPLE
    fav
    List all bookmarks.

.EXAMPLE
    fav -Add -Name hello
    Add current location as bookmark "hello".

.EXAMPLE
    fav 1
    Set location to bookmark id 1.

.EXAMPLE
    fav hello
    Set location to bookmark alias "hello".

.EXAMPLE
    fav -Info
    Print the bookmarks.json file path in use.

.EXAMPLE
    fav -Config D:\my\fav.json -Add -Name work
    Use a custom bookmarks file for this invocation.

.NOTES
    Add to your profile so navigation changes your shell directory:
    function fav { . 'C:\path\to\fav.ps1' @args }
#>
param(
    [Parameter(Position = 0)]
    [string]$Target,

    [switch]$Add,
    [string]$Name,
    [string]$Path,
    [switch]$Remove,
    [int]$Id = -1,
    [switch]$ClearAll,
    [switch]$Info,
    [string]$Config
)

$ErrorActionPreference = 'Stop'

function Resolve-BookmarksFilePath {
    param([string]$CustomPath)
    if ([string]::IsNullOrWhiteSpace($CustomPath)) {
        return Join-Path (Join-Path $env:APPDATA 'fav') 'bookmarks.json'
    }
    if ([System.IO.Path]::IsPathRooted($CustomPath)) {
        return $CustomPath
    }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $CustomPath))
}

$BookmarksFile = Resolve-BookmarksFilePath $Config
$FavDir = Split-Path -Parent $BookmarksFile

function Get-BookmarkStore {
    if (-not (Test-Path -LiteralPath $BookmarksFile)) {
        return [pscustomobject]@{
            nextId    = 1
            bookmarks = @()
        }
    }
    $raw = Get-Content -LiteralPath $BookmarksFile -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{
            nextId    = 1
            bookmarks = @()
        }
    }
    return $raw | ConvertFrom-Json
}

function Save-BookmarkStore {
    param($Store)
    if (-not (Test-Path -LiteralPath $FavDir)) {
        New-Item -ItemType Directory -Path $FavDir -Force | Out-Null
    }
    $Store | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $BookmarksFile -Encoding UTF8
}

function Get-BookmarkList {
    param($Store)
    if ($null -eq $Store.bookmarks) {
        return @()
    }
    @($Store.bookmarks)
}

function Show-Bookmarks {
    param($Store)
    $list = Get-BookmarkList $Store
    if ($list.Count -eq 0) {
        Write-Host 'No bookmarks.'
        return
    }
    $list | Sort-Object { [int]$_.id } | ForEach-Object {
        Write-Host ("{0,3}  {1,-20}  {2}" -f $_.id, $_.name, $_.path)
    }
}

function Resolve-BookmarkPath {
    param([string]$BookmarkPath)
    if (-not (Test-Path -LiteralPath $BookmarkPath)) {
        throw "Bookmark path does not exist: $BookmarkPath"
    }
    (Resolve-Path -LiteralPath $BookmarkPath).Path
}

if ($Info) {
    Write-Output $BookmarksFile
    return
}

if ($ClearAll) {
    $empty = [pscustomobject]@{
        nextId    = 1
        bookmarks = @()
    }
    Save-BookmarkStore $empty
    Write-Host 'All bookmarks removed.'
    return
}

$store = Get-BookmarkStore

if ($Add) {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'Use -Name to specify a bookmark alias.'
    }
    $bookmarkPath = if ([string]::IsNullOrWhiteSpace($Path)) {
        (Get-Location).Path
    }
    else {
        Resolve-BookmarkPath $Path
    }
    $list = @(Get-BookmarkList $store)
    if ($list | Where-Object { $_.name -eq $Name }) {
        throw "Bookmark alias already exists: $Name"
    }
    $newId = [int]$store.nextId
    $entry = [pscustomobject]@{
        id   = $newId
        name = $Name
        path = $bookmarkPath
    }
    $list += $entry
    $store.bookmarks = $list
    $store.nextId = $newId + 1
    Save-BookmarkStore $store
    Write-Host "Added bookmark $newId ($Name) -> $bookmarkPath"
    return
}

if ($Remove) {
    $removeById = $PSBoundParameters.ContainsKey('Id')
    if ($removeById -and -not [string]::IsNullOrWhiteSpace($Name)) {
        throw 'Use either -Id or -Name, not both.'
    }
    if (-not $removeById -and [string]::IsNullOrWhiteSpace($Name)) {
        throw 'Use -Id or -Name to specify which bookmark to remove.'
    }
    $list = @(Get-BookmarkList $store)
    if ($list.Count -eq 0) {
        throw 'No bookmarks to remove.'
    }
    $match = if ($removeById) {
        $list | Where-Object { [int]$_.id -eq $Id }
    }
    else {
        $list | Where-Object { $_.name -eq $Name }
    }
    if (-not $match) {
        $label = if ($removeById) { "id $Id" } else { "name '$Name'" }
        throw "Bookmark not found: $label"
    }
    $removed = @($match)[0]
    $store.bookmarks = @($list | Where-Object { [int]$_.id -ne [int]$removed.id })
    Save-BookmarkStore $store
    Write-Host "Removed bookmark $($removed.id) ($($removed.name))"
    return
}

if ([string]::IsNullOrWhiteSpace($Target)) {
    Show-Bookmarks $store
    return
}

$list = Get-BookmarkList $store
$bookmark = if ($Target -match '^\d+$') {
    $list | Where-Object { [int]$_.id -eq [int]$Target } | Select-Object -First 1
}
else {
    $list | Where-Object { $_.name -eq $Target } | Select-Object -First 1
}

if (-not $bookmark) {
    throw "Bookmark not found: $Target"
}

$dest = Resolve-BookmarkPath $bookmark.path
Set-Location -LiteralPath $dest
Write-Host "-> $dest"
