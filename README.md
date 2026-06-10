# windows-infrastructure-tools

> PowerShell toolkit for Windows infrastructure operations — DNS analysis, KMS activation, RDS license auditing, and more coming soon.

---

## Origin & Disclaimer

These scripts are derived from production workflows used in real enterprise environments.
They have been anonymized, refactored, and generalized for public release.

**Provided as-is, without warranty. Always validate in a lab environment before production use.**

---

## Scripts

| Script | What it does |
|---|---|
| `Get-DNSDebugLog.ps1` | Parses Windows DNS Server debug logs into structured PowerShell objects — used for pre-migration dependency mapping and traffic analysis |
| `Test-KMSActivation.ps1` | Tests KMS server connectivity on port 1688 and activates Windows license via slmgr.vbs — useful during KMS server migrations |
| `Get-RDSLicenseConfig.ps1` | Audits RDS license server configuration across multiple hosts — supports hardcoded list, input file, or Active Directory query |

---

## Get-DNSDebugLog.ps1

Parses Windows DNS Server debug log files into structured PowerShell objects for analysis, reporting, and pre-migration dependency mapping.

**Real-world use case:**
Before migrating on-premises DNS to cloud DNS, this script was used to analyze DNS query traffic — identifying which clients were querying which records, mapping hidden dependencies, and ensuring nothing would break at cutover.

**Features:**
- Parses Windows DNS debug log format (`dns.log`)
- Returns structured objects: Client IP, DateTime, QR, OpCode, QueryType, Query
- `-Ignore` parameter to exclude specific IPs (e.g. domain controllers)
- Fast file reading via `[System.IO.File]::ReadAllText()`
- Progress bar during processing
- Handles malformed lines gracefully — one bad line does not abort the run

**Requirements:** Windows, PowerShell 5.1+, DNS debug logging enabled

**Usage:**

```powershell
# Top 10 clients by query volume
Get-DNSDebugLog -Path "$env:SystemRoot\system32\dns\dns.log" -Verbose |
    Where-Object { $_.QR -eq "Query" -and $_.Way -eq "Rcv" } |
    Group-Object "Client IP" |
    Sort-Object -Descending Count |
    Select-Object -First 10 Name, Count

# Exclude domain controllers from results
$ignore = Get-ADDomainController -Filter * |
    Select-Object -ExpandProperty Hostname |
    ForEach-Object { [System.Net.Dns]::GetHostAddresses($_) |
        Select-Object -ExpandProperty IPAddressToString }

Get-DNSDebugLog -Path "\\dc01.domain.local\c$\dns.log" -Ignore $ignore
```

**Enable DNS debug logging on Windows DNS Server:**

```powershell
dnscmd /config /logLevel 0x6101
dnscmd /config /logFilePath "C:\Windows\System32\dns\dns.log"
dnscmd /config /logFileMaxSize 500000000
```

---

## Test-KMSActivation.ps1

Tests KMS server connectivity on port 1688 and activates Windows via `slmgr.vbs`.
Includes a reusable `Test-Port` function for TCP/UDP port testing.

**Real-world use case:**
Used during KMS server migrations to validate connectivity to the new KMS host before switching activation targets — ensuring no machines get stranded without a valid activation path.

**Features:**
- TCP/UDP port tester with configurable timeout
- Domain detection via `Get-CimInstance`
- KMS host assignment + Windows activation via `slmgr.vbs`
- Exit code validation after each `slmgr` call
- Portable path via `$env:SystemRoot`

**Requirements:** Windows, PowerShell 5.1+, Administrator rights

**Usage:**

```powershell
# Test and activate against a KMS server
.\Test-KMSActivation.ps1 -KMSServer "kms.domain.local"

# Test-Port standalone usage
Test-Port -ComputerName "SERVER01","SERVER02" -Protocol TCP -Port 80,443,1688
```

---

## Get-RDSLicenseConfig.ps1

Audits RDS license server configuration across multiple Remote Desktop hosts via WMI.

**Real-world use case:**
Used during RDS license server migrations to verify all hosts point to the correct license server before decommissioning the old one — across a fleet of RDS servers in seconds instead of clicking through each server's admin console.

**Features:**
- Queries `Root/CIMV2/TerminalServices` WMI namespace remotely
- Returns: ComputerName, LicensingType, LicensingName, SpecifiedLSList, Status
- Three input modes — hardcoded list, text file, or Active Directory OU query
- Graceful error handling — unreachable servers logged as ERROR, processing continues
- `RDSHOST-INVALID` included in default list to demonstrate error handling behavior

**Requirements:** Windows, PowerShell 5.1+, WinRM enabled on target servers

**Usage:**

```powershell
# Hardcoded list
.\Get-RDSLicenseConfig.ps1 -ComputerName "RDSHOST01","RDSHOST02","RDSHOST03"

# From text file
.\Get-RDSLicenseConfig.ps1 -InputFile "C:\servers\rds-hosts.txt"

# From Active Directory OU
.\Get-RDSLicenseConfig.ps1 `
    -SearchBase    "OU=RDS,OU=Servers,DC=domain,DC=local" `
    -ComputerFilter "*RDS*"
```

---

## Repository Structure

| Path | Description |
|---|---|
| `src/Get-DNSDebugLog.ps1` | DNS debug log parser |
| `src/Test-KMSActivation.ps1` | KMS connectivity test + Windows activation |
| `src/Get-RDSLicenseConfig.ps1` | RDS license server configuration audit |
| `examples/` | Example invocations |
| `docs/images/` | Architecture diagrams |
| `LICENSE` | License file |
| `README.md` | This file |

---

## Requirements summary

| Requirement | Details |
|---|---|
| PowerShell | 5.1 or later |
| OS | Windows |
| Privileges | Administrator (Test-KMSActivation) |
| WinRM | Enabled on target servers (Get-RDSLicenseConfig) |
| DNS debug log | Enabled on DNS server (Get-DNSDebugLog) |

---

## Credits

`Get-DNSDebugLog` is based on original work by **Ov** — [http://virot.eu](http://virot.eu).
Extended and improved by Brahim O.

`Test-Port` function adapted from **PoshFunctions** by Bill Riedy —
[PowerShell Gallery](https://www.powershellgallery.com/packages/PoshFunctions).
Originally inspired by [TechNet Script Center](https://gallery.technet.microsoft.com/scriptcenter/97119ed6-6fb2-446d-98d8-32d823867131).

---

## Author

**Brahim O.**

---

## License

This project is licensed under the terms of the [LICENSE](LICENSE) file.
