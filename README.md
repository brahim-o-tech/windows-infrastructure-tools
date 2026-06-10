# windows-infrastructure-tools

> PowerShell toolkit for Windows infrastructure operations — DNS debug log analysis, and more coming soon.

---

## Origin & Disclaimer

These scripts are derived from production workflows used in real enterprise environments.
They have been anonymized, refactored, and generalized for public release.

**Provided as-is, without warranty. Always validate in a lab environment before production use.**

---

## Scripts

### `Get-DNSDebugLog.ps1`

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
# Enable via dnscmd
dnscmd /config /logLevel 0x6101
dnscmd /config /logFilePath "C:\Windows\System32\dns\dns.log"
dnscmd /config /logFileMaxSize 500000000
```

---

## Repository Structure

| Path | Description |
|---|---|
| `src/Get-DNSDebugLog.ps1` | DNS debug log parser |
| `examples/` | Example invocations |
| `docs/images/` | Architecture diagrams |
| `LICENSE` | License file |
| `README.md` | This file |

---

## Coming soon

- KMS / RDS license server migration toolkit
- More Windows infrastructure automation scripts

---

## Credits

`Get-DNSDebugLog` is based on original work by **Ov** — [http://virot.eu](http://virot.eu).
Extended, corrected, and improved by Brahim O.

---

## Author

**Brahim O.**

---

## License

This project is licensed under the terms of the [LICENSE](LICENSE) file.
