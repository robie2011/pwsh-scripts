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
    Context 'Get-FilesMatchingGlob (glob pattern matching)' {
    # ------------------------------------------------------------------

        It 'finds appsettings.json in the root directory' {
            New-FileWithContent (Join-Path $script:Source 'appsettings.json')

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            Test-Path (Join-Path $script:Target 'appsettings.json') | Should -Be $true
        }

        It 'finds appsettings.Development.json' {
            New-FileWithContent (Join-Path $script:Source 'appsettings.Development.json')

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            Test-Path (Join-Path $script:Target 'appsettings.Development.json') | Should -Be $true
        }

        It 'finds launchSettings.json only within a Properties subfolder' {
            New-FileWithContent (Join-Path $script:Source 'Properties\launchSettings.json')
            New-FileWithContent (Join-Path $script:Source 'launchSettings.json')  # should be ignored

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            Test-Path (Join-Path $script:Target 'Properties\launchSettings.json') | Should -Be $true
            Test-Path (Join-Path $script:Target 'launchSettings.json') | Should -Be $false
        }

        It 'finds appsettings.json in a subfolder' {
            New-FileWithContent (Join-Path $script:Source 'MyApp\appsettings.json')

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            Test-Path (Join-Path $script:Target 'MyApp\appsettings.json') | Should -Be $true
        }

        It 'finds .env files' {
            New-FileWithContent (Join-Path $script:Source '.env')

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            Test-Path (Join-Path $script:Target '.env') | Should -Be $true
        }

        It 'finds .env.local files' {
            New-FileWithContent (Join-Path $script:Source '.env.local')

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            Test-Path (Join-Path $script:Target '.env.local') | Should -Be $true
        }

        It 'excludes non-matching files' {
            New-FileWithContent (Join-Path $script:Source 'README.md')
            New-FileWithContent (Join-Path $script:Source 'Program.cs')

            $result = Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            }

            $result | Should -Match 'No matching'
        }
    }

    # ------------------------------------------------------------------
    Context '-WhatIf' {
    # ------------------------------------------------------------------

        It 'does not copy files when -WhatIf is set' {
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

        It 'overwrites existing file without prompting' {
            New-FileWithContent (Join-Path $script:Source 'appsettings.json') 'new'
            New-FileWithContent (Join-Path $script:Target 'appsettings.json') 'old'

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            Get-Content (Join-Path $script:Target 'appsettings.json') -Raw | Should -Match 'new'
        }

        It 'outputs "Copied:" for each copied file' {
            New-FileWithContent (Join-Path $script:Source 'appsettings.json')

            $output = Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            }

            $output | Should -Match 'Copied:'
        }
    }

    # ------------------------------------------------------------------
    Context 'Copying files (new files)' {
    # ------------------------------------------------------------------

        It 'copies file to the target directory' {
            New-FileWithContent (Join-Path $script:Source 'appsettings.json') 'content'

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            Test-Path (Join-Path $script:Target 'appsettings.json') | Should -Be $true
        }

        It 'creates missing subdirectories in the target' {
            New-FileWithContent (Join-Path $script:Source 'MyApp\Properties\launchSettings.json')

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            } | Out-Null

            Test-Path (Join-Path $script:Target 'MyApp\Properties\launchSettings.json') | Should -Be $true
        }

        It 'copies file content correctly' {
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

        It 'does not copy the same file twice (deduplication across patterns)' {
            New-FileWithContent (Join-Path $script:Source 'appsettings.json')

            $output = Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
            }

            ($output | Where-Object { $_ -match 'Copied:.*appsettings\.json' }).Count | Should -Be 1
        }
    }

    # ------------------------------------------------------------------
    Context '-Include' {
    # ------------------------------------------------------------------

        It 'copies files specified via -Include' {
            New-FileWithContent (Join-Path $script:Source 'custom.json') 'custom'

            Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
                Include    = @('**/custom.json')
            } | Out-Null

            Test-Path (Join-Path $script:Target 'custom.json') | Should -Be $true
        }

        It 'combines -Include with default patterns' {
            New-FileWithContent (Join-Path $script:Source 'appsettings.json')
            New-FileWithContent (Join-Path $script:Source 'extra.config')

            $output = Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
                Force      = $true
                Include    = @('**/extra.config')
            }

            ($output | Where-Object { $_ -match 'Copied:.*appsettings\.json' }).Count | Should -Be 1
            ($output | Where-Object { $_ -match 'Copied:.*extra\.config' }).Count | Should -Be 1
        }
    }

    # ------------------------------------------------------------------
    Context 'Error: source equals target' {
    # ------------------------------------------------------------------

        It 'reports an error when SourcePath and TargetPath are identical' {
            $output = Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Source
            }
            $output | Should -Match 'identical'
        }
    }

    # ------------------------------------------------------------------
    Context 'No files found' {
    # ------------------------------------------------------------------

        It 'reports that no files were found' {
            $output = Invoke-CopyConfig -Params @{
                SourcePath = $script:Source
                TargetPath = $script:Target
            }
            $output | Should -Match 'No matching'
        }
    }
}
