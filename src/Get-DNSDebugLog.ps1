Function Get-DNSDebugLog 
{ # Parses the DNS debug log
    <# 
            .SYNOPSIS 
            Reads the specified DNS debug log. 
 
            .DESCRIPTION 
            Retrives all entries in the DNS debug log for further processing using powershell or exporting to Excel. 
 
            .PARAMETER Path 
            Specifies the path to the DNS debug logfile. 
 
            .PARAMETER Ignore 
            Specifies which IPs to ignore. 
 
            .INPUTS 
            Takes the filepath of the DNS servers debug log. 
            And an Ignore parameter to ignore certain ips. 
 
            .OUTPUTS 
            Array of PSCustomObject 
 
            \windows\system32\dns\dns.log 
 
            .EXAMPLE 
            Get-DNSDebugLog -Path "$($env:SystemRoot)\system32\dns\dns.log" -Verbose | ? {$_.QR -eq "Query"-and $_.Way -eq 'RCV'} | group-Object "Client IP"| Sort-Object -Descending Count| Select -First 10 Name, Count 
 
            Name Count 
            ---- ----- 
            192.168.66.103 21 
            192.168.66.37 11 
            192.168.66.22 4 
            192.168.66.117 1 
 
 
            .EXAMPLE 
            C:\PS> Import-Module ActiveDirectory 
            C:\PS> $ignore = Get-ADDomainController -Filter * | Select-Object -ExpandProperty Hostname |ForEach-Object {[System.Net.Dns]::GetHostAddresses($_)|select -ExpandProperty IPAddressToString} 
            C:\PS> Get-DNSDebugLog -Ignore:$Ignore -Path '\\dc01.domain.tld\c$\dns.log' 
 
            .LINK 
            Original script by Ov — http://virot.eu
            Extended and improved by Brahim O.

            .NOTES 
            Author          : Brahim O.
            Based on        : Original work by Ov (http://virot.eu)
            Version         : 1.1
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]
        [ValidateScript({Test-Path($_)})]
        $Path,
        
        [Parameter(Mandatory=$False)]
        [string[]]
        $Ignore
    )
    
    Begin
    {
        Write-Verbose "Storing DNS logfile format"
        $dnspattern = "^([0-9]{1,2}\/[0-9]{1,2}\/[0-9]{2,4}|[0-9]{2,4}-[0-9]{2}-[0-9]{2}) ([0-9: ]{7,8}\s?P?A?M?) ([0-9A-Z]{3,4} PACKET\s*[0-9A-Za-z]{8,16}) (UDP|TCP) (Snd|Rcv) ([0-9 .]{7,15}) ([0-9a-z]{4}) (.) (.) \[.*\] (.*) (\(.*)"
        Write-Verbose "Storing returning customobject format"
        $returnselect = @{label="Client IP";expression={($temp[6]).trim()}},
        @{label="DateTime";expression={
            # FIX BUG 2 — Use invariant culture for reliable date parsing across system locales
            try {
                [DateTime]::Parse("$($temp[1]) $($temp[2])", [System.Globalization.CultureInfo]::InvariantCulture)
            }
            catch {
                [DateTime]::Parse("$($temp[1]) $($temp[2])")
            }
        }},
        @{label="QR";expression={switch($temp[8]){" " {'Query'};"R" {'Response'}}}},
        @{label="OpCode";expression={switch($temp[9]){'Q' {'Standard Query'};'N' {'Notify'};'U' {'Update'};'?' {'Unknown'}}}},
        @{label="Way";expression={$temp[5]}},
        @{label="QueryType";expression={($temp[10]).Trim()}},
        @{label="Query";expression={$temp[11] -replace "(`\(.*)","`$1" -replace "`\(.*?`\)","." -replace "^.",""}}
    }
    
    Process
    {
        Write-Verbose "Getting the contents of $Path, and matching for correct rows."

        # FIX BUG 1 — Replace ls alias with Get-Item
        $file    = Get-Item -Path $Path
        $objFile = [System.IO.File]::ReadAllText($file.FullName)
        $rows    = $objFile.split("`n") -match $dnspattern -notmatch 'ERROR offset' -notmatch 'NOTIMP'

        Write-Verbose "Found $($rows.count) rows in debuglog, processing 1 at a time."

        # FIX BUG 3 — Guard against division by zero on empty log
        if ($rows.Count -eq 0) {
            Write-Verbose "No matching rows found in debug log. Exiting."
            return
        }
        
        [int]$intTracker = 0
                
        ForEach ($row in $rows)
        {
            Try
            {
                $temp = $Null
                $temp = [regex]::split($row,$dnspattern)

                # FIX BUG 4 — Compare as string not [ipaddress] — type mismatch caused Ignore to never work
                if ($Ignore -notcontains ($temp[6]).trim())
                {
                    $true | Select-Object $returnselect
                }
            }
            Catch
            {
                $strFailedRow = 'Failed to interpet row.'
                Write-Verbose $strFailedRow
                Write-Debug $strFailedRow
                Write-Debug $row
            }

            $perc = ($intTracker / $rows.Count * 100)
            Write-Progress -PercentComplete $perc -Activity "Processing $intTracker of $($rows.Count)" `
            -Status 'File analysis progress'
            $intTracker++
        }
    }
}
