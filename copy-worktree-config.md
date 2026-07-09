# copy-worktree-config.ps1

Copies environment-specific config files from the main Git worktree into the current worktree.

Config files (e.g. `appsettings.json`, `.env`) are typically listed in `.gitignore` and therefore missing when a new worktree is created. This script lets you pull them in with a single command.

## Requirements

- PowerShell 5.1 or later
- When `-SourcePath` is omitted, the script must be run from within a linked Git worktree (not the main checkout)

## Usage

```powershell
.\copy-worktree-config.ps1 [-Force] [-Include <String[]>] [-SourcePath <String>] [-WhatIf] [-Confirm]
```

## Parameters

| Parameter | Type | Description |
|---|---|---|
| `-Force` | Switch | Overwrite existing files in the target without prompting |
| `-Include` | `String[]` | Additional glob patterns on top of the built-in defaults |
| `-SourcePath` | `String` | Optional source path. Defaults to the main worktree detected via `git worktree list` |
| `-WhatIf` | Switch | Preview which files would be copied without making any changes |
| `-Confirm` | Switch | Prompt for confirmation before each copy operation |

Without `-Force`, the script prompts for each file that already exists in the target:

| Choice | Meaning |
|---|---|
| **Y**es | Overwrite this file |
| **A**ll | Overwrite all remaining files without further prompting |
| **N**o | Skip this file |
| **C**ancel | Stop the script |

## Default Patterns

The following file patterns are matched by default:

| Pattern | Description |
|---|---|
| `**/Properties/launchSettings.json` | ASP.NET launch profiles |
| `**/appsettings.json` | .NET base configuration |
| `**/appsettings.*.json` | .NET environment-specific configuration |
| `**/.env` | Environment variable files |
| `**/.env.*` | Environment-specific `.env` files (e.g. `.env.local`) |

## Examples

```powershell
# Interactive: prompts before overwriting existing files
.\copy-worktree-config.ps1

# Preview: shows what would be copied
.\copy-worktree-config.ps1 -WhatIf

# Overwrite everything without prompting
.\copy-worktree-config.ps1 -Force

# Add extra patterns on top of the defaults
.\copy-worktree-config.ps1 -Include '**/custom.json', '**/*.config'

# Copy from a specific source path instead of the main worktree
.\copy-worktree-config.ps1 -SourcePath 'D:\repos\my-project'
```

## Notes

- The directory structure of source files is preserved in the target worktree
- Missing subdirectories in the target are created automatically
- Files matching multiple patterns are only copied once (deduplication)
