Describe 'Stop-ProcessOnPort' {
    BeforeAll {
        $script:StopProcessOnPortScript = (Resolve-Path (Join-Path $PSScriptRoot '..' 'Stop-ProcessOnPort.ps1')).Path

        function Invoke-StopProcessOnPort {
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
            & $script:StopProcessOnPortScript @splat 6>&1 | ForEach-Object { "$_" }
        }
    }

    Context 'listener detection' {
        It 'throws when no process is listening on the port' {
            Mock Get-NetTCPConnection { @() }
            Mock Get-NetUDPEndpoint { @() }

            { Invoke-StopProcessOnPort -Params @{ Port = 3000 } } | Should -Throw -ExpectedMessage '*No process is listening*'
        }
    }

    Context 'process termination' {
        It 'stops a TCP listener process' {
            Mock Get-NetTCPConnection { @([pscustomobject]@{ OwningProcess = 1234 }) }
            Mock Get-NetUDPEndpoint { @() }
            Mock Get-Process { [pscustomobject]@{ Id = 1234; ProcessName = 'node' } } -ParameterFilter { $Id -eq 1234 }
            Mock Stop-Process {}

            $output = Invoke-StopProcessOnPort -Params @{ Port = 3000 }

            Assert-MockCalled Stop-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 1234 -and $Force }
            ($output -join "`n") | Should -Match 'Stopped process 1234 \(node\) listening on port 3000'
        }

        It 'stops each unique process id once across TCP and UDP listeners' {
            Mock Get-NetTCPConnection {
                @(
                    [pscustomobject]@{ OwningProcess = 1111 },
                    [pscustomobject]@{ OwningProcess = 2222 }
                )
            }
            Mock Get-NetUDPEndpoint { @([pscustomobject]@{ OwningProcess = 1111 }) }
            Mock Get-Process {
                if ($Id -eq 1111) { return [pscustomobject]@{ Id = 1111; ProcessName = 'proc-a' } }
                if ($Id -eq 2222) { return [pscustomobject]@{ Id = 2222; ProcessName = 'proc-b' } }
                throw "Unexpected process id $Id"
            }
            Mock Stop-Process {}

            Invoke-StopProcessOnPort -Params @{ Port = 8080 } | Out-Null

            Assert-MockCalled Stop-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 1111 -and $Force }
            Assert-MockCalled Stop-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 2222 -and $Force }
            Assert-MockCalled Stop-Process -Times 2 -Exactly
        }
    }
}
