Describe 'copy-worktree-config' {

    BeforeAll {
        $script:CopyScript = (Resolve-Path (Join-Path $PSScriptRoot '..' 'copy-worktree-config.ps1')).Path

        function Invoke-CopyConfig {
            param([hashtable]$Params = @{})
            $splat = @{}
            foreach ($key in $Params.Keys) {
                $value = $Params[$key]
                if ($value -is [bool]) {
                    if ($value) { $splat[$key] = $true }
                    continue
                }
                if ($value -is [switch]) {
                    if ($value.IsPresent) { $splat[$key] = $true }
                    continue
                }
                $splat[$key] = $value
            }
            try {
                & $script:CopyScript @splat 2>&1 6>&1 | ForEach-Object { "$_" }
            } catch {
                "$_"
            }
        }

        function New-TempDir {
            $path = Join-Path $TestDrive ("wt-{0}" -f [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            return $path
        }

        function New-FileWithContent {
            param([string]$Path, [string]$Content = 'test')
            $dir = Split-Path -Parent $Path
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
        }
    }

    BeforeEach {
        $script:Source = New-TempDir
        $script:Target = New-TempDir
    }

    # ------------------------------------------------------------------
    Context 'Get-FilesMatchingGlob (Glob-Pattern-Matching)' {
    # ------------------------------------------------------------------

        It 'findet appsettings.json im Stammverzeichnis' {
            New-FileWithContent (Join-Path $script:Source 'appsettings.json')

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            Test-Path (Join-Path $script:Target 'appsettings.json') | Should -Be $true
        }

        It 'findet appsettings.Development.json' {
            New-FileWithContent (Join-Path $script:Source 'appsettings.Development.json')

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            Test-Path (Join-Path $script:Target 'appsettings.Development.json') | Should -Be $true
        }

        It 'findet launchSettings.json nur in einem Properties-Unterordner' {
            New-FileWithContent (Join-Path $script:Source 'Properties\launchSettings.json')
            New-FileWithContent (Join-Path $script:Source 'launchSettings.json')  # soll ignoriert werden

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            Test-Path (Join-Path $script:Target 'Properties\launchSettings.json') | Should -Be $true
            Test-Path (Join-Path $script:Target 'launchSettings.json') | Should -Be $false
        }

        It 'findet appsettings.json in einem Unterordner' {
            New-FileWithContent (Join-Path $script:Source 'MyApp\appsettings.json')

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            Test-Path (Join-Path $script:Target 'MyApp\appsettings.json') | Should -Be $true
        }

        It 'findet .env Dateien' {
            New-FileWithContent (Join-Path $script:Source '.env')

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            Test-Path (Join-Path $script:Target '.env') | Should -Be $true
        }

        It 'findet .env.local Dateien' {
            New-FileWithContent (Join-Path $script:Source '.env.local')

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            Test-Path (Join-Path $script:Target '.env.local') | Should -Be $true
        }

        It 'schliesst nicht passende Dateien aus' {
            New-FileWithContent (Join-Path $script:Source 'README.md')
            New-FileWithContent (Join-Path $script:Source 'Program.cs')

            $result = Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            }

            $result | Should -Match 'Keine passenden'
        }
    }

    # ------------------------------------------------------------------
    Context '-WhatIf' {
    # ------------------------------------------------------------------

        It 'kopiert keine Dateien wenn -WhatIf gesetzt ist' {
            New-FileWithContent (Join-Path $script:Source 'appsettings.json') 'original'

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                WhatIf     = $true
            } | Out-Null

            Test-Path (Join-Path $script:Target 'appsettings.json') | Should -Be $false
        }
    }

    # ------------------------------------------------------------------
    Context '-Force' {
    # ------------------------------------------------------------------

        It 'überschreibt bestehende Datei ohne Nachfrage' {
            New-FileWithContent (Join-Path $script:Source 'appsettings.json') 'neu'
            New-FileWithContent (Join-Path $script:Target 'appsettings.json') 'alt'

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            Get-Content (Join-Path $script:Target 'appsettings.json') -Raw | Should -Match 'neu'
        }

        It 'gibt "Kopiert:" für jede kopierte Datei aus' {
            New-FileWithContent (Join-Path $script:Source 'appsettings.json')

            $output = Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            }

            $output | Should -Match 'Kopiert:'
        }
    }

    # ------------------------------------------------------------------
    Context 'Datei kopieren (neue Dateien)' {
    # ------------------------------------------------------------------

        It 'kopiert Datei in den Zielordner' {
            New-FileWithContent (Join-Path $script:Source 'appsettings.json') 'inhalt'

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            Test-Path (Join-Path $script:Target 'appsettings.json') | Should -Be $true
        }

        It 'erstellt fehlende Unterordner im Ziel' {
            New-FileWithContent (Join-Path $script:Source 'MyApp\Properties\launchSettings.json')

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            Test-Path (Join-Path $script:Target 'MyApp\Properties\launchSettings.json') | Should -Be $true
        }

        It 'kopiert Dateiinhalt korrekt' {
            $content = '{"key":"value"}'
            New-FileWithContent (Join-Path $script:Source 'appsettings.json') $content

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            $copied = Get-Content (Join-Path $script:Target 'appsettings.json') -Raw
            $copied.Trim() | Should -Be $content
        }

        It 'kopiert dieselbe Datei nicht doppelt (Duplikate via mehrere Patterns)' {
            New-FileWithContent (Join-Path $script:Source 'appsettings.json')

            $output = Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            }

            ($output | Where-Object { $_ -match 'Kopiert:.*appsettings\.json' }).Count | Should -Be 1
        }
    }

    # ------------------------------------------------------------------
    Context '-Include' {
    # ------------------------------------------------------------------

        It 'kopiert Dateien die zusätzlich per -Include angegeben werden' {
            New-FileWithContent (Join-Path $script:Source 'custom.json') 'custom'

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
                Include    = @('**/custom.json')
            } | Out-Null

            Test-Path (Join-Path $script:Target 'custom.json') | Should -Be $true
        }

        It 'kombiniert -Include mit den Defaults' {
            New-FileWithContent (Join-Path $script:Source 'appsettings.json')
            New-FileWithContent (Join-Path $script:Source 'extra.config')

            $output = Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
                Include    = @('**/extra.config')
            }

            ($output | Where-Object { $_ -match 'Kopiert:.*appsettings\.json' }).Count | Should -Be 1
            ($output | Where-Object { $_ -match 'Kopiert:.*extra\.config' }).Count | Should -Be 1
        }
    }

    # ------------------------------------------------------------------
    Context 'Fehlerfall: Quelle gleich Ziel' {
    # ------------------------------------------------------------------

        It 'gibt Fehlermeldung aus wenn SourcePath und TargetPath identisch sind' {
            $output = Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Source
            }
            $output | Should -Match 'identisch'
        }
    }

    # ------------------------------------------------------------------
    Context 'Keine Dateien gefunden' {
    # ------------------------------------------------------------------

        It 'meldet, dass keine Dateien gefunden wurden' {
            $output = Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
            }
            $output | Should -Match 'Keine passenden'
        }
    }
}
