# snippets.ps1

CLI template helper for PowerShell. Save reusable commands with optional working directories, search them by keyword, and run them from the shell.

## Requirements

- PowerShell 5.1 or later
- Windows (`notepad.exe` used for `-Add`; `$env:APPDATA` for default storage)

## Profile setup

Dot-source the script so `-Run` and `-ChangeDirectory` affect your current shell session:

```powershell
function snippets { . 'C:\path\to\pwsh-scripts\snippets.ps1' @args }
```

## Persistence

Default store file:

```
%APPDATA%\snippets\snippets.json
```

The parent directory is created automatically on first save. Override the path per invocation with `-Config` (absolute or relative to the current directory).

### JSON schema

```json
{
  "nextId": 1,
  "snippets": [
    {
      "id": 1,
      "name": "build",
      "description": "Run local build",
      "command": "dotnet build",
      "workingDirectory": "C:\\repos\\myapp"
    }
  ]
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `nextId` | — | Next id to assign; not decremented when snippets are removed |
| `snippets[].id` | auto | Assigned on save |
| `snippets[].name` | yes | Unique snippet name |
| `snippets[].description` | no | Free-text description |
| `snippets[].command` | yes | PowerShell command executed via `Invoke-Expression` |
| `snippets[].workingDirectory` | no | Directory to `Set-Location` before running |

## Commands

| Command | Description |
|---------|-------------|
| `snippets` | List all snippets (`id`, `name`, `description`) |
| `snippets <keyword> [<keyword> ...]` | Search snippets (AND logic, case-insensitive) |
| `snippets keyword-search <keyword> ...` | Same as positional search (alias) |
| `snippets -Add` | Open Notepad with a JSON template; save on exit |
| `snippets -Add -Interactive` | Prompt for each field via `Read-Host` |
| `snippets -Run <id\|name>` | Change directory (if set), substitute variables, run command |
| `snippets -ChangeDirectory <id\|name>` | `Set-Location` to snippet working directory |
| `snippets -Remove -Id <id>` | Remove snippet by id |
| `snippets -Remove -Name <name>` | Remove snippet by name |
| `snippets -ClearAll` | Delete all snippets and reset `nextId` to 1 |
| `snippets -Info` | Print the active config file path |
| `snippets -Config <path> ...` | Use a custom JSON file for this invocation |

### Dispatch priority

1. `-Info`
2. `-ClearAll`
3. `-Add`
4. `-Remove`
5. `-Run`
6. `-ChangeDirectory`
7. List (no positional arguments)
8. Search (one or more positional keywords)

### Search behavior

- Every keyword must match (AND) as a case-insensitive substring.
- Fields searched: `name`, `description`, `command`, `workingDirectory`.
- Output is key-value detail per match, with a blank line between results.

### Variable placeholders

Commands may contain `$$VARIABLE$$` placeholders. On `-Run`, each unique variable name is prompted once via `Read-Host` and substituted before execution.

Example command:

```text
docker run -e TOKEN=$$TOKEN$$ myimage
```

## Examples

```powershell
snippets                                    # list
snippets docker build                       # search
snippets -Add                               # add via Notepad JSON
snippets -Add -Interactive                  # add via prompts
snippets -Run build                         # run by name
snippets -ChangeDirectory 1                 # cd to snippet id 1
snippets -Remove -Name build
snippets -ClearAll
snippets -Info
```

### Notepad add template

`snippets -Add` opens a temp file pre-filled with:

```json
{
  "name": "",
  "description": "",
  "command": "",
  "workingDirectory": ""
}
```

Fill in the fields, save, and close Notepad. `name` and `command` are required; `workingDirectory` is validated if provided.

## Internal functions

| Function | Purpose |
|----------|---------|
| `Resolve-SnippetsFilePath` | Resolve default or custom config path |
| `Get-SnippetStore` / `Save-SnippetStore` | Load and persist JSON store |
| `Get-SnippetList` | Normalize `snippets` array |
| `Show-Snippets` | Table list output |
| `Show-SnippetDetail` | Key-value detail output for search results |
| `Find-SnippetsByKeywords` | AND keyword search |
| `Get-SnippetByTarget` | Lookup by numeric id or name |
| `Resolve-SnippetWorkingDirectory` | Validate and resolve directory path |
| `Set-SnippetLocation` | `Set-Location` for `-ChangeDirectory` |
| `Expand-SnippetCommand` | Replace `$$VAR$$` placeholders |
| `New-SnippetInputFromObject` | Validate input from JSON or interactive prompts |
| `Add-SnippetFromObject` | Shared save path for add flows |
| `Invoke-SnippetAddFromNotepad` | Temp file + Notepad editor flow |
| `Invoke-SnippetAddInteractive` | `Read-Host` prompt flow |
| `Get-SearchKeywords` | Strip optional `keyword-search` prefix |
| `Get-ActionTarget` | Resolve single id/name for `-Run` / `-ChangeDirectory` |

## Error handling

`$ErrorActionPreference = 'Stop'` is set at script scope. Validation errors (missing name/command, duplicate name, invalid path, invalid JSON, not found) throw terminating errors.

## Testing

Tests live in [`tests/snippets.Tests.ps1`](tests/snippets.Tests.ps1). Each test uses an isolated config file under Pester's `$TestDrive` via `-Config`.

```powershell
Invoke-Pester -Path .\tests\snippets.Tests.ps1
```

Test helpers:

- `Invoke-Snippets` — run the script and capture output as strings
- `Invoke-SnippetsWithConfig` — same, with `-Config` bound to a temp file
- `Set-TestSnippetStore` / `New-TestSnippetObject` — seed store data without Notepad

Notepad and `Start-Process` are not invoked in CI. Add-path logic is tested via dot-sourcing (` . .\snippets.ps1 -Info -Config <path>`) to call `Add-SnippetFromObject` directly.

Run the full suite:

```powershell
Invoke-Pester -Path .\tests
```

## Development notes

- Ids are never reused after removal; only `-ClearAll` resets `nextId`.
- `-Run` uses `Invoke-Expression`; snippets run in the caller's session with the caller's permissions.
- Snippet names must be unique; lookup by id uses exact numeric match, by name uses exact string match.
- The script is a single file with no module manifest; all logic is inline for easy dot-sourcing.
