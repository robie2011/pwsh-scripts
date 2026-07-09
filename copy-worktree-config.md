# copy-worktree-config.ps1

Kopiert environment-spezifische Config-Dateien vom Haupt-Git-Worktree in den aktuellen Worktree.

Da Config-Dateien (z. B. `appsettings.json`, `.env`) typischerweise in `.gitignore` stehen und daher beim Erstellen eines neuen Worktrees fehlen, lassen sie sich mit diesem Script schnell nachziehen.

## Voraussetzungen

- PowerShell 5.1 oder neuer
- Das Script muss innerhalb eines verlinkten Git-Worktrees ausgeführt werden

## Verwendung

```powershell
.\copy-worktree-config.ps1 [-Force] [-Include <String[]>] [-SourcePath <String>] [-WhatIf]
```

## Parameter

| Parameter | Typ | Beschreibung |
|---|---|---|
| `-Force` | Switch | Bestehende Dateien im Ziel ohne Nachfrage überschreiben |
| `-Include` | `String[]` | Zusätzliche Glob-Patterns (ergänzend zu den Defaults) |
| `-SourcePath` | `String` | Optionaler Quellpfad. Standardmässig wird der Haupt-Worktree via `git worktree list` ermittelt |
| `-WhatIf` | Switch | Zeigt an, was kopiert werden würde, ohne Änderungen vorzunehmen |

Ohne `-Force` fragt das Script bei jeder Datei nach, die im Ziel bereits existiert:

| Auswahl | Bedeutung |
|---|---|
| **J**a | Diese Datei überschreiben |
| **A**lle | Alle weiteren Dateien ohne Nachfrage überschreiben |
| **N**ein | Diese Datei überspringen |
| **A**bbrechen | Script beenden |

## Standard-Patterns

Folgende Dateimuster werden standardmässig berücksichtigt:

| Pattern | Beschreibung |
|---|---|
| `**/Properties/launchSettings.json` | ASP.NET Startprofil |
| `**/appsettings.json` | .NET Basis-Konfiguration |
| `**/appsettings.*.json` | .NET umgebungsspezifische Konfiguration |
| `**/.env` | Environment-Variablen |
| `**/.env.*` | Umgebungsspezifische `.env`-Dateien (z. B. `.env.local`) |

## Beispiele

```powershell
# Interaktiv: fragt nach bei bestehenden Dateien
.\copy-worktree-config.ps1

# Vorschau: zeigt was kopiert werden würde
.\copy-worktree-config.ps1 -WhatIf

# Alles ohne Nachfrage überschreiben
.\copy-worktree-config.ps1 -Force

# Zusätzliche Patterns mitgeben
.\copy-worktree-config.ps1 -Include '**/custom.json', '**/*.config'

# Aus einem anderen Quellpfad kopieren
.\copy-worktree-config.ps1 -SourcePath 'D:\repos\mein-projekt'
```

## Hinweise

- Die Ordnerstruktur der Quelldateien wird im Ziel-Worktree beibehalten
- Fehlende Unterordner im Ziel werden automatisch erstellt
- Duplikate (Dateien, die auf mehrere Patterns passen) werden nur einmal kopiert
