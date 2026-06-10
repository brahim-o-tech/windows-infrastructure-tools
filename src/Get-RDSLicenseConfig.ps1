#Requires -Version 5.1

<#
.SYNOPSIS
    Audits RDS license server configuration across one or more Remote Desktop hosts.

.DESCRIPTION
    Queries the WMI namespace Root/CIMV2/TerminalServices on each target server
    to retrieve the configured license server list, licensing type, and licensing name.

    Useful during RDS license server migrations — verify all hosts point to the
    correct license server before decommissioning the old one.

    Input options:
      - Hardcoded list (small environments)
      - Text file with one server per line (-InputFile)
      - Active Directory OU query (-SearchBase)
      - AD name pattern (-ComputerFilter)

.PARAMETER ComputerName
    One or more RDS host names to query. Used for small hardcoded lists.

.PARAMETER InputFile
    Path to a text file containing one server name per line.

.PARAMETER SearchBase
    Active Directory OU distinguished name to query for RDS servers.
    Example: "OU=RDS,OU=Servers,DC=domain,DC=local"

.PARAMETER ComputerFilter
    AD computer name filter when using -SearchBase.
    Example: "*RDS*"

.EXAMPLE
    # Hardcoded list
    .\Get-RDSLicenseConfig.ps1 -ComputerName "RDSHOST01","RDSHOST02","RDSHOST03"

.EXAMPLE
    # From text file
    .\Get-RDSLicenseConfig.ps1 -InputFile "C:\servers\rds-hosts.txt"

.EXAMPLE
    # From Active Directory OU
    .\Get-RDSLicenseConfig.ps1 -SearchBase "OU=RDS,OU=Servers,DC=domain,DC=local" -ComputerFilter "*RDS*"

.NOTES
    Author      : Brahim O.
    Version     : 1.1
    Requires    : PowerShell 5.1+, WinRM enabled on target servers
                  ActiveDirectory module (only if using -SearchBase)
#>

[CmdletBinding(DefaultParameterSetName = 'Direct')]
param(
    [Parameter(ParameterSetName = 'Direct')]
    [string[]]$ComputerName = @(
        "RDSHOST01",
        "RDSHOST02",
        "RDSHOST03",
        "RDSHOST-INVALID"  # intentionally invalid — used to validate error handling
    ),

    [Parameter(ParameterSetName = 'File')]
    [ValidateScript({ Test-Path $_ })]
    [string]$InputFile,

    [Parameter(ParameterSetName = 'AD')]
    [string]$SearchBase,

    [Parameter(ParameterSetName = 'AD')]
    [string]$ComputerFilter = "*RDS*"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    switch ($Level) {
        "ERROR"   { Write-Host $entry -ForegroundColor Red    }
        "SUCCESS" { Write-Host $entry -ForegroundColor Green  }
        "WARN"    { Write-Host $entry -ForegroundColor Yellow }
        default   { Write-Host $entry }
    }
}

# ============================================================
#  Build computer list from selected input method
# ============================================================

$computers = [System.Collections.Generic.List[string]]::new()

switch ($PSCmdlet.ParameterSetName) {

    'Direct' {
        Write-Log "Using hardcoded computer list ($($ComputerName.Count) entries)"
        $ComputerName | ForEach-Object { $computers.Add($_) }
    }

    'File' {
        Write-Log "Loading computer list from file: $InputFile"
        Get-Content $InputFile |
            Where-Object { $_ -match '\S' } |
            ForEach-Object { $computers.Add($_.Trim()) }
        Write-Log "Loaded $($computers.Count) server(s) from file" "SUCCESS"
    }

    'AD' {
        Write-Log "Querying Active Directory — SearchBase: $SearchBase | Filter: $ComputerFilter"
        Import-Module ActiveDirectory -ErrorAction Stop
        Get-ADComputer -Filter "Name -like '$ComputerFilter'" -SearchBase $SearchBase |
            Select-Object -ExpandProperty Name |
            ForEach-Object { $computers.Add($_) }
        Write-Log "Found $($computers.Count) server(s) in AD" "SUCCESS"
    }
}

if ($computers.Count -eq 0) {
    Write-Log "No servers to process. Exiting." "WARN"
    exit 0
}

Write-Log "Servers to query: $($computers.Count)"

# ============================================================
#  ScriptBlock — runs on each remote server via Invoke-Command
# ============================================================

$scriptBlock = {
    # FIX BUG 2 — gwmi deprecated, replaced by Get-CimInstance
    $result = Get-CimInstance `
        -Namespace "Root/CIMV2/TerminalServices" `
        -ClassName Win32_TerminalServiceSetting

    $licenseServers = try {
        ($result | Invoke-CimMethod -MethodName GetSpecifiedLicenseServerList).SpecifiedLSList
    }
    catch { "n/a" }

    [PSCustomObject]@{
        ComputerName    = $result.PSComputerName
        ServerName      = $result.ServerName
        # FIX BUG 3 — LicensingType and LicensingName were swapped in original
        LicensingType   = $result.LicensingType
        LicensingName   = $result.LicensingName
        SpecifiedLSList = $licenseServers
    }
}

# ============================================================
#  Query each server
# ============================================================

# FIX BUG 4 — List instead of $arr += pattern
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($computer in $computers) {
    try {
        Write-Log "Querying: $computer"
        $result = Invoke-Command `
            -ComputerName $computer `
            -ScriptBlock  $scriptBlock `
            -ErrorAction  Stop

        $result.ComputerName = $computer

        $results.Add([PSCustomObject]@{
            ComputerName    = $computer
            ServerName      = $result.ServerName
            LicensingType   = $result.LicensingType
            LicensingName   = $result.LicensingName
            SpecifiedLSList = $result.SpecifiedLSList
            Status          = "OK"
        })

        Write-Log "OK: $computer — LicenseServer: $($result.SpecifiedLSList)" "SUCCESS"
    }
    catch {
        Write-Log "FAILED: $computer — $($_.Exception.Message)" "ERROR"

        $results.Add([PSCustomObject]@{
            ComputerName    = $computer
            ServerName      = "n/a"
            LicensingType   = "n/a"
            LicensingName   = "n/a"
            SpecifiedLSList = "n/a"
            Status          = "ERROR: $($_.Exception.Message)"
        })
    }
}

# ============================================================
#  Output
# ============================================================

Write-Host ""
Write-Log "Results — $($results.Count) server(s) queried"
Write-Host ""

# FIX BUG 5 — Write-Output before Format-Table is redundant
$results | Format-Table -AutoSize

$ok     = @($results | Where-Object { $_.Status -eq "OK" }).Count
$failed = @($results | Where-Object { $_.Status -ne "OK" }).Count

Write-Host ""
Write-Log "Successful : $ok"     "SUCCESS"
Write-Log "Failed     : $failed" $(if ($failed -gt 0) { "ERROR" } else { "SUCCESS" })
