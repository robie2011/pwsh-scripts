$script:FavScript = (Resolve-Path (Join-Path $PSScriptRoot '..' 'fav.ps1')).Path

function Invoke-Fav {
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
    & $script:FavScript @splat 6>&1 | ForEach-Object { "$_" }
}

function Invoke-FavWithConfig {
    param([hashtable]$Params = @{})
    $merged = @{ Config = $script:BookmarksFile }
    foreach ($key in $Params.Keys) { $merged[$key] = $Params[$key] }
    Invoke-Fav -Params $merged
}

function Get-TestBookmarkStore {
    if (-not (Test-Path -LiteralPath $script:BookmarksFile)) {
        return $null
    }
    Get-Content -LiteralPath $script:BookmarksFile -Raw | ConvertFrom-Json
}

Describe 'fav' {
    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive ("fav-{0}" -f ([guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
        $script:BookmarksFile = Join-Path $script:TestRoot 'bookmarks.json'
        $script:SamplePath = (Resolve-Path $TestDrive).Path
    }

    AfterEach {
        Set-Location $env:TEMP
    }

    Context '-Info' {
        It 'prints default bookmarks.json path when -Config is omitted' {
            $output = Invoke-Fav -Params @{ Info = $true }
            $expected = Join-Path $env:APPDATA 'fav\bookmarks.json'
            $output | Should Be $expected
        }

        It 'prints custom bookmarks file when -Config is set' {
            $custom = Join-Path $script:TestRoot 'custom.json'
            $output = Invoke-Fav -Params @{ Info = $true; Config = $custom }
            $output | Should Be $custom
        }
    }

    Context '-Add' {
        It 'adds a bookmark with explicit path' {
            { Invoke-FavWithConfig -Params @{ Add = $true; Name = 'work'; Path = $script:SamplePath } } |
                Should Not Throw

            $store = Get-TestBookmarkStore
            $store.bookmarks.Count | Should Be 1
            $store.bookmarks[0].id | Should Be 1
            $store.bookmarks[0].name | Should Be 'work'
            $store.bookmarks[0].path | Should Be $script:SamplePath
            $store.nextId | Should Be 2
        }

        It 'uses current location when -Path is omitted' {
            Push-Location $script:SamplePath
            try {
                { Invoke-FavWithConfig -Params @{ Add = $true; Name = 'here' } } | Should Not Throw
                $store = Get-TestBookmarkStore
                $store.bookmarks[0].path | Should Be $script:SamplePath
            }
            finally {
                Pop-Location
            }
        }

        It 'increments bookmark ids' {
            Invoke-FavWithConfig -Params @{ Add = $true; Name = 'a'; Path = $script:SamplePath } | Out-Null
            Invoke-FavWithConfig -Params @{ Add = $true; Name = 'b'; Path = $script:SamplePath } | Out-Null
            $store = Get-TestBookmarkStore
            @($store.bookmarks | ForEach-Object { [int]$_.id }) | Should Be @(1, 2)
        }

        It 'throws when alias already exists' {
            Invoke-FavWithConfig -Params @{ Add = $true; Name = 'dup'; Path = $script:SamplePath } | Out-Null
            { Invoke-FavWithConfig -Params @{ Add = $true; Name = 'dup'; Path = $script:SamplePath } } |
                Should Throw 'already exists'
        }

        It 'throws when -Name is missing' {
            { Invoke-FavWithConfig -Params @{ Add = $true } } | Should Throw '-Name'
        }
    }

    Context 'list' {
        It 'reports no bookmarks when store is empty' {
            $output = Invoke-FavWithConfig -Params @{}
            ($output -join "`n") | Should Match 'No bookmarks'
        }

        It 'lists saved bookmarks' {
            Invoke-FavWithConfig -Params @{ Add = $true; Name = 'one'; Path = $script:SamplePath } | Out-Null
            $output = Invoke-FavWithConfig -Params @{}
            $text = $output -join "`n"
            $text | Should Match 'one'
            $text | Should Match ([regex]::Escape($script:SamplePath))
        }
    }

    Context 'navigate' {
        It 'navigates by numeric id' {
            Invoke-FavWithConfig -Params @{ Add = $true; Name = 'go'; Path = $script:SamplePath } | Out-Null
            $output = Invoke-FavWithConfig -Params @{ Target = '1' }
            ($output -join "`n") | Should Match ([regex]::Escape("-> $script:SamplePath"))
        }

        It 'navigates by alias' {
            Invoke-FavWithConfig -Params @{ Add = $true; Name = 'alias'; Path = $script:SamplePath } | Out-Null
            $output = Invoke-FavWithConfig -Params @{ Target = 'alias' }
            ($output -join "`n") | Should Match ([regex]::Escape("-> $script:SamplePath"))
        }

        It 'throws when bookmark is not found' {
            { Invoke-FavWithConfig -Params @{ Target = 'missing' } } | Should Throw 'not found'
        }
    }

    Context '-Remove' {
        BeforeEach {
            Invoke-FavWithConfig -Params @{ Add = $true; Name = 'a'; Path = $script:SamplePath } | Out-Null
            Invoke-FavWithConfig -Params @{ Add = $true; Name = 'b'; Path = $script:SamplePath } | Out-Null
        }

        It 'removes bookmark by id' {
            Invoke-FavWithConfig -Params @{ Remove = $true; Id = 1 } | Out-Null
            $store = Get-TestBookmarkStore
            $store.bookmarks.Count | Should Be 1
            $store.bookmarks[0].name | Should Be 'b'
        }

        It 'removes bookmark by name' {
            Invoke-FavWithConfig -Params @{ Remove = $true; Name = 'b' } | Out-Null
            $store = Get-TestBookmarkStore
            $store.bookmarks.Count | Should Be 1
            $store.bookmarks[0].name | Should Be 'a'
        }

        It 'throws when both -Id and -Name are given' {
            { Invoke-FavWithConfig -Params @{ Remove = $true; Id = 1; Name = 'a' } } |
                Should Throw 'either -Id or -Name'
        }

        It 'throws when neither -Id nor -Name is given' {
            { Invoke-FavWithConfig -Params @{ Remove = $true } } | Should Throw '-Id or -Name'
        }

        It 'throws when bookmark does not exist' {
            { Invoke-FavWithConfig -Params @{ Remove = $true; Id = 99 } } | Should Throw 'not found'
        }
    }

    Context '-ClearAll' {
        It 'removes all bookmarks' {
            Invoke-FavWithConfig -Params @{ Add = $true; Name = 'x'; Path = $script:SamplePath } | Out-Null
            Invoke-FavWithConfig -Params @{ ClearAll = $true } | Out-Null
            $store = Get-TestBookmarkStore
            $store.bookmarks.Count | Should Be 0
            $store.nextId | Should Be 1
        }
    }

    Context '-Config' {
        It 'creates parent directories for a nested custom file' {
            $nested = Join-Path $script:TestRoot 'nested\bookmarks.json'
            Invoke-Fav -Params @{ Config = $nested; Add = $true; Name = 'n'; Path = $script:SamplePath } | Out-Null
            Test-Path -LiteralPath $nested | Should Be $true
            $store = Get-Content -LiteralPath $nested -Raw | ConvertFrom-Json
            $store.bookmarks.Count | Should Be 1
        }

        It 'isolates bookmarks per config file' {
            $fileA = Join-Path $script:TestRoot 'a.json'
            $fileB = Join-Path $script:TestRoot 'b.json'
            Invoke-Fav -Params @{ Config = $fileA; Add = $true; Name = 'only-a'; Path = $script:SamplePath } | Out-Null
            Invoke-Fav -Params @{ Config = $fileB; Add = $true; Name = 'only-b'; Path = $script:SamplePath } | Out-Null

            $storeA = Get-Content -LiteralPath $fileA -Raw | ConvertFrom-Json
            $storeB = Get-Content -LiteralPath $fileB -Raw | ConvertFrom-Json
            $storeA.bookmarks.name | Should Be 'only-a'
            $storeB.bookmarks.name | Should Be 'only-b'
        }
    }
}
