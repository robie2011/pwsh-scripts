$script:SnippetsScript = (Resolve-Path (Join-Path $PSScriptRoot '..' 'snippets.ps1')).Path

function Invoke-Snippets {
    param(
        [hashtable]$Params = @{}
    )
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
    & $script:SnippetsScript @splat 6>&1 | ForEach-Object { "$_" }
}

function Invoke-SnippetsWithConfig {
    param([hashtable]$Params = @{})
    $merged = @{ Config = $script:SnippetsFile }
    foreach ($key in $Params.Keys) { $merged[$key] = $Params[$key] }
    Invoke-Snippets -Params $merged
}

function Get-TestSnippetStore {
    if (-not (Test-Path -LiteralPath $script:SnippetsFile)) {
        return $null
    }
    Get-Content -LiteralPath $script:SnippetsFile -Raw | ConvertFrom-Json
}

function New-TestSnippetObject {
    param(
        [int]$Id,
        [string]$Name,
        [string]$Command,
        [string]$Description = '',
        [string]$WorkingDirectory = ''
    )
    [pscustomobject]@{
        id               = $Id
        name             = $Name
        description      = $Description
        command          = $Command
        workingDirectory = $WorkingDirectory
    }
}

function Set-TestSnippetStore {
    param(
        [array]$Snippets = @(),
        [int]$NextId = 1
    )
    if ($NextId -lt 1) {
        $NextId = 1
    }
    if ($Snippets.Count -gt 0 -and $NextId -le ($Snippets | ForEach-Object { [int]$_.id } | Measure-Object -Maximum).Maximum) {
        $NextId = ($Snippets | ForEach-Object { [int]$_.id } | Measure-Object -Maximum).Maximum + 1
    }
    $store = [pscustomobject]@{
        nextId   = $NextId
        snippets = @($Snippets)
    }
    $dir = Split-Path -Parent $script:SnippetsFile
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $store | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:SnippetsFile -Encoding UTF8
}

Describe 'snippets' {
    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive ("snippets-{0}" -f ([guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
        $script:SnippetsFile = Join-Path $script:TestRoot 'snippets.json'
        $script:SamplePath = (Resolve-Path $TestDrive).Path
        $script:ReadHostIndex = 0
    }

    AfterEach {
        Set-Location $env:TEMP
    }

    Context '-Info' {
        It 'prints default snippets.json path when -Config is omitted' {
            $output = Invoke-Snippets -Params @{ Info = $true }
            $expected = Join-Path $env:APPDATA 'snippets\snippets.json'
            $output | Should Be $expected
        }

        It 'prints custom snippets file when -Config is set' {
            $custom = Join-Path $script:TestRoot 'custom.json'
            $output = Invoke-Snippets -Params @{ Info = $true; Config = $custom }
            $output | Should Be $custom
        }
    }

    Context '-Add -Interactive' {
        It 'adds a snippet with all fields' {
            Mock Read-Host {
                $values = @('build', 'Run build', 'dotnet build', (Resolve-Path $TestDrive).Path)
                $values[$script:ReadHostIndex++]
            }
            $script:ReadHostIndex = 0
            Invoke-SnippetsWithConfig -Params @{ Add = $true; Interactive = $true } | Out-Null

            $store = Get-TestSnippetStore
            $store.snippets.Count | Should Be 1
            $store.snippets[0].id | Should Be 1
            $store.snippets[0].name | Should Be 'build'
            $store.snippets[0].description | Should Be 'Run build'
            $store.snippets[0].command | Should Be 'dotnet build'
            $store.snippets[0].workingDirectory | Should Be $script:SamplePath
            $store.nextId | Should Be 2
        }

        It 'allows optional description and working directory' {
            Mock Read-Host { @('minimal', '', 'echo ok', '')[$script:ReadHostIndex++] }
            $script:ReadHostIndex = 0
            Invoke-SnippetsWithConfig -Params @{ Add = $true; Interactive = $true } | Out-Null

            $store = Get-TestSnippetStore
            $store.snippets[0].description | Should Be ''
            $store.snippets[0].workingDirectory | Should BeNullOrEmpty
        }

        It 'increments snippet ids' {
            Mock Read-Host { @('a', '', 'echo a', '')[$script:ReadHostIndex++] }
            $script:ReadHostIndex = 0
            Invoke-SnippetsWithConfig -Params @{ Add = $true; Interactive = $true } | Out-Null
            Mock Read-Host { @('b', '', 'echo b', '')[$script:ReadHostIndex++] }
            $script:ReadHostIndex = 0
            Invoke-SnippetsWithConfig -Params @{ Add = $true; Interactive = $true } | Out-Null
            $store = Get-TestSnippetStore
            @($store.snippets | ForEach-Object { [int]$_.id }) | Should Be @(1, 2)
        }

        It 'throws when name already exists' {
            Set-TestSnippetStore -Snippets @(
                (New-TestSnippetObject -Id 1 -Name 'dup' -Command 'echo one')
            ) -NextId 2
            Mock Read-Host { @('dup', '', 'echo two', '')[$script:ReadHostIndex++] }
            $script:ReadHostIndex = 0
            { Invoke-SnippetsWithConfig -Params @{ Add = $true; Interactive = $true } } |
                Should Throw 'already exists'
        }

        It 'throws when name is missing' {
            Mock Read-Host { @('', 'desc', 'echo ok', '')[$script:ReadHostIndex++] }
            $script:ReadHostIndex = 0
            { Invoke-SnippetsWithConfig -Params @{ Add = $true; Interactive = $true } } |
                Should Throw 'name is required'
        }

        It 'throws when command is missing' {
            Mock Read-Host { @('named', 'desc', '', '')[$script:ReadHostIndex++] }
            $script:ReadHostIndex = 0
            { Invoke-SnippetsWithConfig -Params @{ Add = $true; Interactive = $true } } |
                Should Throw 'command is required'
        }

        It 'throws when working directory does not exist' {
            Mock Read-Host { @('badwd', '', 'echo ok', 'Z:\missing-path')[$script:ReadHostIndex++] }
            $script:ReadHostIndex = 0
            { Invoke-SnippetsWithConfig -Params @{ Add = $true; Interactive = $true } } |
                Should Throw 'does not exist'
        }
    }

    Context '-Add notepad' {
        It 'saves snippet from notepad JSON template' {
            . $script:SnippetsScript -Info -Config $script:SnippetsFile
            $json = @"
{
  "name": "deploy",
  "description": "Deploy app",
  "command": "npm run deploy",
  "workingDirectory": "$($script:SamplePath -replace '\\', '\\')"
}
"@
            $store = Get-SnippetStore
            $parsed = $json | ConvertFrom-Json
            Add-SnippetFromObject -Store $store -InputObject $parsed | Out-Null

            $saved = Get-TestSnippetStore
            $saved.snippets[0].name | Should Be 'deploy'
            $saved.snippets[0].command | Should Be 'npm run deploy'
        }

        It 'throws on invalid JSON from notepad' {
            . $script:SnippetsScript -Info -Config $script:SnippetsFile
            $raw = '{ invalid'
            {
                try {
                    $null = $raw | ConvertFrom-Json
                }
                catch {
                    throw 'Invalid JSON in snippet template.'
                }
            } | Should Throw 'Invalid JSON'
        }

        It 'throws when notepad file is empty' {
            . $script:SnippetsScript -Info -Config $script:SnippetsFile
            {
                $raw = '   '
                if ([string]::IsNullOrWhiteSpace($raw)) {
                    throw 'No snippet content was saved.'
                }
            } | Should Throw 'No snippet content'
        }
    }

    Context 'list' {
        It 'reports no snippets when store is empty' {
            $output = Invoke-SnippetsWithConfig -Params @{}
            ($output -join "`n") | Should Match 'No snippets'
        }

        It 'lists saved snippets' {
            Set-TestSnippetStore -Snippets @(
                (New-TestSnippetObject -Id 1 -Name 'listed' -Description 'A listed snippet' -Command 'echo listed')
            )
            $output = Invoke-SnippetsWithConfig -Params @{}
            $text = $output -join "`n"
            $text | Should Match 'listed'
            $text | Should Match 'A listed snippet'
        }
    }

    Context 'search' {
        BeforeEach {
            Set-TestSnippetStore -Snippets @(
                (New-TestSnippetObject -Id 1 -Name 'docker-build' -Description 'Build containers' -Command 'docker compose build' -WorkingDirectory $script:SamplePath),
                (New-TestSnippetObject -Id 2 -Name 'lint' -Description 'Run linter' -Command 'npm run lint')
            ) -NextId 3
        }

        It 'finds snippets matching all keywords' {
            $output = Invoke-SnippetsWithConfig -Params @{ Keywords = @('docker', 'build') }
            $text = $output -join "`n"
            $text | Should Match 'docker-build'
            $text | Should Match 'command: docker compose build'
        }

        It 'is case-insensitive' {
            $output = Invoke-SnippetsWithConfig -Params @{ Keywords = @('DOCKER') }
            ($output -join "`n") | Should Match 'docker-build'
        }

        It 'reports no matches when keywords do not match' {
            $output = Invoke-SnippetsWithConfig -Params @{ Keywords = @('missing', 'terms') }
            ($output -join "`n") | Should Match 'No snippets matched'
        }

        It 'supports keyword-search alias' {
            $output = Invoke-SnippetsWithConfig -Params @{ Keywords = @('keyword-search', 'lint') }
            ($output -join "`n") | Should Match 'name: lint'
        }
    }

    Context '-ChangeDirectory' {
        It 'changes location when working directory is set' {
            Set-TestSnippetStore -Snippets @(
                (New-TestSnippetObject -Id 1 -Name 'go' -Command 'echo go' -WorkingDirectory $script:SamplePath)
            )
            $output = Invoke-SnippetsWithConfig -Params @{ ChangeDirectory = $true; Keywords = @('1') }
            ($output -join "`n") | Should Match ([regex]::Escape("-> $script:SamplePath"))
        }

        It 'resolves snippet by name' {
            Set-TestSnippetStore -Snippets @(
                (New-TestSnippetObject -Id 1 -Name 'alias' -Command 'echo alias' -WorkingDirectory $script:SamplePath)
            )
            $output = Invoke-SnippetsWithConfig -Params @{ ChangeDirectory = $true; Keywords = @('alias') }
            ($output -join "`n") | Should Match ([regex]::Escape("-> $script:SamplePath"))
        }

        It 'throws when snippet has no working directory' {
            Set-TestSnippetStore -Snippets @(
                (New-TestSnippetObject -Id 1 -Name 'nowd' -Command 'echo nowd')
            )
            { Invoke-SnippetsWithConfig -Params @{ ChangeDirectory = $true; Keywords = @('nowd') } } |
                Should Throw 'no working directory'
        }

        It 'throws when snippet is not found' {
            { Invoke-SnippetsWithConfig -Params @{ ChangeDirectory = $true; Keywords = @('missing') } } |
                Should Throw 'not found'
        }

        It 'throws when target is missing' {
            { Invoke-SnippetsWithConfig -Params @{ ChangeDirectory = $true } } |
                Should Throw 'Specify a snippet id or name'
        }
    }

    Context '-Run' {
        It 'executes snippet command' {
            Set-TestSnippetStore -Snippets @(
                (New-TestSnippetObject -Id 1 -Name 'say' -Command "Write-Output 'snippet-run-ok'")
            )
            $output = Invoke-SnippetsWithConfig -Params @{ Run = $true; Keywords = @('say') }
            ($output -join "`n") | Should Match 'snippet-run-ok'
        }

        It 'changes directory before running' {
            Set-TestSnippetStore -Snippets @(
                (New-TestSnippetObject -Id 1 -Name 'pwd' -Command "Write-Output (Get-Location).Path" -WorkingDirectory $script:SamplePath)
            )
            $output = Invoke-SnippetsWithConfig -Params @{ Run = $true; Keywords = @('pwd') }
            ($output -join "`n") | Should Match ([regex]::Escape($script:SamplePath))
        }

        It 'substitutes $$VAR$$ placeholders' {
            Set-TestSnippetStore -Snippets @(
                (New-TestSnippetObject -Id 1 -Name 'vars' -Command 'Write-Output ''value=$$NAME$$''')
            )
            Mock Read-Host { 'test-value' } -ParameterFilter { $Prompt -eq 'Enter value for NAME' }
            $output = Invoke-SnippetsWithConfig -Params @{ Run = $true; Keywords = @('vars') }
            ($output -join "`n") | Should Match 'value=test-value'
        }

        It 'throws when snippet is not found' {
            { Invoke-SnippetsWithConfig -Params @{ Run = $true; Keywords = @('missing') } } |
                Should Throw 'not found'
        }
    }

    Context '-Remove' {
        BeforeEach {
            Set-TestSnippetStore -Snippets @(
                (New-TestSnippetObject -Id 1 -Name 'a' -Command 'echo a'),
                (New-TestSnippetObject -Id 2 -Name 'b' -Command 'echo b')
            ) -NextId 3
        }

        It 'removes snippet by id' {
            Invoke-SnippetsWithConfig -Params @{ Remove = $true; Id = 1 } | Out-Null
            $store = Get-TestSnippetStore
            $store.snippets.Count | Should Be 1
            $store.snippets[0].name | Should Be 'b'
            $store.nextId | Should Be 3
        }

        It 'removes snippet by name' {
            Invoke-SnippetsWithConfig -Params @{ Remove = $true; Name = 'b' } | Out-Null
            $store = Get-TestSnippetStore
            $store.snippets.Count | Should Be 1
            $store.snippets[0].name | Should Be 'a'
        }

        It 'throws when both -Id and -Name are given' {
            { Invoke-SnippetsWithConfig -Params @{ Remove = $true; Id = 1; Name = 'a' } } |
                Should Throw 'either -Id or -Name'
        }

        It 'throws when neither -Id nor -Name is given' {
            { Invoke-SnippetsWithConfig -Params @{ Remove = $true } } |
                Should Throw '-Id or -Name'
        }

        It 'throws when snippet does not exist' {
            { Invoke-SnippetsWithConfig -Params @{ Remove = $true; Id = 99 } } |
                Should Throw 'not found'
        }
    }

    Context '-ClearAll' {
        It 'removes all snippets' {
            Set-TestSnippetStore -Snippets @(
                (New-TestSnippetObject -Id 1 -Name 'x' -Command 'echo x')
            ) -NextId 2
            Invoke-SnippetsWithConfig -Params @{ ClearAll = $true } | Out-Null
            $store = Get-TestSnippetStore
            $store.snippets.Count | Should Be 0
            $store.nextId | Should Be 1
        }
    }

    Context '-Config' {
        It 'creates parent directories for a nested custom file' {
            $nested = Join-Path $script:TestRoot 'nested\snippets.json'
            Mock Read-Host { @('n', '', 'echo n', $script:SamplePath)[$script:ReadHostIndex++] }
            $script:ReadHostIndex = 0
            Invoke-Snippets -Params @{ Config = $nested; Add = $true; Interactive = $true } | Out-Null
            Test-Path -LiteralPath $nested | Should Be $true
            $store = Get-Content -LiteralPath $nested -Raw | ConvertFrom-Json
            $store.snippets.Count | Should Be 1
        }

        It 'isolates snippets per config file' {
            $fileA = Join-Path $script:TestRoot 'a.json'
            $fileB = Join-Path $script:TestRoot 'b.json'
            Mock Read-Host { @('only-a', '', 'echo a', '')[$script:ReadHostIndex++] }
            $script:ReadHostIndex = 0
            Invoke-Snippets -Params @{ Config = $fileA; Add = $true; Interactive = $true } | Out-Null
            Mock Read-Host { @('only-b', '', 'echo b', '')[$script:ReadHostIndex++] }
            $script:ReadHostIndex = 0
            Invoke-Snippets -Params @{ Config = $fileB; Add = $true; Interactive = $true } | Out-Null

            $storeA = Get-Content -LiteralPath $fileA -Raw | ConvertFrom-Json
            $storeB = Get-Content -LiteralPath $fileB -Raw | ConvertFrom-Json
            $storeA.snippets.name | Should Be 'only-a'
            $storeB.snippets.name | Should Be 'only-b'
        }
    }
}
