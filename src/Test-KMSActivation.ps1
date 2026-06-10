#Requires -Version 5.1

<#
.SYNOPSIS
    Tests KMS server connectivity and activates Windows license via KMS.

.DESCRIPTION
    This script combines a generic TCP/UDP port tester with KMS-specific
    connectivity validation and Windows activation via slmgr.vbs.

    Workflow:
      1. Tests KMS server availability on port 1688 (TCP)
      2. Detects the current domain
      3. If KMS is reachable — sets KMS host and activates Windows
      4. Displays license status via slmgr -dli

    Useful during KMS server migrations to validate connectivity
    before switching activation targets.

.PARAMETER KMSServer
    FQDN or IP of the KMS server to test and activate against.

.PARAMETER KMSPort
    KMS port — defaults to 1688.

.EXAMPLE
    .\Test-KMSActivation.ps1 -KMSServer "kms.domain.local"

.EXAMPLE
    .\Test-KMSActivation.ps1 -KMSServer "kms.domain.local" -KMSPort 1688

.NOTES
    Author      : Brahim O.
    Version     : 1.1
    Requires    : PowerShell 5.1+, Windows, Administrator rights
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$KMSServer,

    [int]$KMSPort = 1688
)

#region Test-Port function

function Test-Port {
    <#
    .SYNOPSIS
        Tests for open TCP/UDP ports.
    .DESCRIPTION
        Tests any TCP/UDP port to see if it is open or closed.
    .NOTES
        Known Issue: If called within 10-20 consecutive times on the same UDP port
        and computer, the UDP check may output $false incorrectly.
    .PARAMETER ComputerName
        One or more remote computer names.
    .PARAMETER Port
        One or more port numbers to test.
    .PARAMETER Protocol
        The protocol to test — TCP or UDP.
    .PARAMETER TcpTimeout
        Milliseconds to wait before declaring TCP port closed. Default: 1000.
    .PARAMETER UdpTimeout
        Milliseconds to wait before declaring UDP port closed. Default: 1000.
    .EXAMPLE
        Test-Port -ComputerName 'SERVER01','SERVER02' -Protocol TCP -Port 80,443
    #>
    [CmdletBinding(DefaultParameterSetName = 'TCP')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [string[]]$ComputerName,

        [Parameter(Mandatory)]
        [int[]]$Port,

        [Parameter(Mandatory)]
        [ValidateSet('TCP', 'UDP')]
        [string]$Protocol,

        [Parameter(ParameterSetName = 'TCP')]
        [int]$TcpTimeout = 1000,

        [Parameter(ParameterSetName = 'UDP')]
        [int]$UdpTimeout = 1000
    )

    process {
        foreach ($Computer in $ComputerName) {
            foreach ($Portx in $Port) {

                $Output = @{
                    ComputerName = $Computer
                    Port         = $Portx
                    Protocol     = $Protocol
                    Result       = $false
                }

                Write-Verbose "$($MyInvocation.MyCommand.Name) - Testing '$Computer' on port '$Protocol`:$Portx'"

                if ($Protocol -eq 'TCP') {
                    $TcpClient = New-Object System.Net.Sockets.TcpClient
                    try {
                        $Connect = $TcpClient.BeginConnect($Computer, $Portx, $null, $null)
                        $Wait    = $Connect.AsyncWaitHandle.WaitOne($TcpTimeout, $false)

                        if (-not $Wait) {
                            Write-Verbose "$($MyInvocation.MyCommand.Name) - '$Computer' FAILED on port '$Protocol`:$Portx'"
                            $Output.Result = $false
                        }
                        else {
                            $TcpClient.EndConnect($Connect)
                            Write-Verbose "$($MyInvocation.MyCommand.Name) - '$Computer' PASSED on port '$Protocol`:$Portx'"
                            $Output.Result = $true
                        }
                    }
                    finally {
                        $TcpClient.Close()
                        $TcpClient.Dispose()
                    }
                }
                elseif ($Protocol -eq 'UDP') {
                    $UdpClient = New-Object System.Net.Sockets.UdpClient
                    try {
                        $UdpClient.Client.ReceiveTimeout = $UdpTimeout
                        $UdpClient.Connect($Computer, $Portx)

                        Write-Verbose "$($MyInvocation.MyCommand.Name) - Sending UDP probe to '$Computer' on port '$Portx'"
                        $encoder  = New-Object System.Text.ASCIIEncoding
                        $byte     = $encoder.GetBytes("$(Get-Date)")
                        [void]$UdpClient.Send($byte, $byte.Length)

                        $remoteEndpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)

                        try {
                            $receiveBytes = $UdpClient.Receive([ref]$remoteEndpoint)
                            $returnData   = $encoder.GetString($receiveBytes)
                            if ($returnData) {
                                Write-Verbose "$($MyInvocation.MyCommand.Name) - '$Computer' PASSED on port '$Protocol`:$Portx'"
                                $Output.Result = $true
                            }
                        }
                        catch {
                            Write-Verbose "$($MyInvocation.MyCommand.Name) - '$Computer' FAILED on port '$Protocol`:$Portx' — $($_.Exception.Message)"
                            $Output.Result = $false
                        }
                    }
                    finally {
                        $UdpClient.Close()
                        $UdpClient.Dispose()
                    }
                }

                [PSCustomObject]$Output
            }
        }
    }
}

#endregion

#region Main

# FIX BUG 1 — Get-WMIObject deprecated, replaced by Get-CimInstance
$domain = (Get-CimInstance Win32_ComputerSystem).Domain
Write-Host "Detected domain : $domain" -ForegroundColor Green
Write-Host "KMS server      : $KMSServer" -ForegroundColor Green
Write-Host "KMS port        : $KMSPort" -ForegroundColor Green
Write-Host ""

Write-Host "Testing KMS connectivity on port $KMSPort..." -ForegroundColor Cyan

# FIX BUG 4 — Compare [bool] with -eq $true instead of -like "True"
$kmsReachable = (Test-Port -ComputerName $KMSServer -Port $KMSPort -Protocol TCP -Verbose).Result -eq $true

if ($kmsReachable) {
    Write-Host "KMS server '$KMSServer' reachable on port $KMSPort." -ForegroundColor Green
    Write-Host ""
    Write-Host "Proceeding with KMS activation..." -ForegroundColor Cyan

    try {
        # FIX BUG 3 — $env:SystemRoot instead of hardcoded C:\Windows
        # FIX BUG 2 — Check $LASTEXITCODE after each cscript call
        $slmgr = "$env:SystemRoot\System32\slmgr.vbs"

        Write-Host "Setting KMS host: $KMSServer"
        cscript $slmgr -skms $KMSServer
        if ($LASTEXITCODE -ne 0) { throw "slmgr -skms failed (exit code $LASTEXITCODE)" }

        Write-Host "Activating Windows..."
        cscript $slmgr -ato
        if ($LASTEXITCODE -ne 0) { throw "slmgr -ato failed (exit code $LASTEXITCODE)" }

        Write-Host ""
        Write-Host "License status:" -ForegroundColor Cyan
        cscript $slmgr -dli

        Write-Host ""
        Write-Host "KMS activation completed successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Activation failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Warning "KMS server '$KMSServer' NOT reachable on port $KMSPort. Activation aborted."
}

#endregion
