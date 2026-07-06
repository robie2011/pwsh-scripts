# fav.ps1

Filesystem bookmark helper for PowerShell. Save directory paths by name or numeric id and jump to them from the CLI.

## Requirements

- PowerShell 5.1 or later
- Windows (`$env:APPDATA` used for default storage)

## Profile setup

Dot-source the script so `Set-Location` affects your current shell session:

```powershell
function fav { . 'C:\path\to\pwsh-scripts\fav.ps1' @args }
```

## Persistence

Default store file:

```
%APPDATA%\fav\bookmarks.json
```

The parent directory is created automatically on first save. Override the path per invocation with `-Config` (absolute or relative to the current directory).

### JSON schema

```json
{
  "nextId": 1,
  "bookmarks": [
    {
      "id": 1,
      "name": "work",
      "path": "C:\\repos\\myapp"
    }
  ]
}
```

| Field | Description |
|-------|-------------|
| `nextId` | Next id to assign; not decremented when bookmarks are removed |
| `bookmarks[].id` | Auto-assigned numeric id |
| `bookmarks[].name` | Unique alias (string) |
| `bookmarks[].path` | Absolute resolved directory path |

## Commands

| Command | Description |
|---------|-------------|
| `fav` | List all bookmarks (`id`, `name`, `path`) |
| `fav <id>` | Navigate to bookmark by numeric id |
| `fav <name>` | Navigate to bookmark by alias |
| `fav -Add -Name <alias>` | Save current directory as a bookmark |
| `fav -Add -Name <alias> -Path <dir>` | Save a specific directory |
| `fav -Remove -Id <id>` | Remove bookmark by id |
| `fav -Remove -Name <alias>` | Remove bookmark by alias |
| `fav -ClearAll` | Delete all bookmarks and reset `nextId` to 1 |
| `fav -Info` | Print the active config file path |
| `fav -Config <path> ...` | Use a custom JSON file for this invocation |

### Dispatch priority

1. `-Info`
2. `-ClearAll`
3. `-Add`
4. `-Remove`
5. List (no positional argument)
6. Navigate (positional `Target`)

## Examples

```powershell
fav                              # list
fav -Add -Name hello             # bookmark current directory
fav hello                        # cd to bookmark
fav 1                            # cd by id
fav -Remove -Name hello
fav -Info
```

## Internal functions

| Function | Purpose |
|----------|---------|
| `Resolve-BookmarksFilePath` | Resolve default or custom config path |
| `Get-BookmarkStore` | Load store from disk (or return empty store) |
| `Save-BookmarkStore` | Persist store as UTF-8 JSON |
| `Get-BookmarkList` | Normalize `bookmarks` array from store |
| `Show-Bookmarks` | Format table output |
| `Resolve-BookmarkPath` | Validate path exists and return resolved absolute path |

## Error handling

`$ErrorActionPreference = 'Stop'` is set at script scope. Missing bookmarks, duplicate names, invalid paths, and invalid `-Remove` argument combinations throw terminating errors with descriptive messages.

## Testing

Tests live in [`tests/fav.Tests.ps1`](tests/fav.Tests.ps1). Each test uses an isolated config file under Pester's `$TestDrive` via `-Config`.

```powershell
Invoke-Pester -Path .\tests\fav.Tests.ps1
```

Test helpers:

- `Invoke-Fav` — run the script and capture output as strings
- `Invoke-FavWithConfig` — same, with `-Config` bound to a temp file

## Development notes

- Ids are never reused after removal; only `-ClearAll` resets `nextId`.
- Paths are validated at add and navigate time; moved or deleted directories cause navigate to fail.
- The script is a single file with no module manifest; all logic is inline for easy dot-sourcing.
