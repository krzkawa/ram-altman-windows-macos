# Windows 10/11 port; compatible with Windows PowerShell 5.1.
param([Parameter(Position=0)][string]$Action = "")
$ErrorActionPreference = "Stop"
$Recipient=$env:RAM_ALTMAN_TO; $Sender=$env:RAM_ALTMAN_FROM; $SenderName=$env:RAM_ALTMAN_FROM_NAME
$Threshold=10.0
if ($env:RAM_ALTMAN_THRESHOLD) {
 if (-not [double]::TryParse($env:RAM_ALTMAN_THRESHOLD,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$Threshold)) { throw "RAM_ALTMAN_THRESHOLD must be numeric." }
}
if ($Threshold -lt 0 -or $Threshold -gt 100) { throw "RAM_ALTMAN_THRESHOLD must be from 0 to 100." }
$StateDir=$env:RAM_ALTMAN_STATE_DIR
if (-not $StateDir) { $StateDir=Join-Path $env:LOCALAPPDATA "ram-altman" }
$LogPath=Join-Path $StateDir "usage.csv"; $LastPath=Join-Path $StateDir "last_sent"
function Get-Memory {
 $os=Get-CimInstance Win32_OperatingSystem
 $total=[int64]$os.TotalVisibleMemorySize; $free=[int64]$os.FreePhysicalMemory; $standby=[int64]0
 try {
  $c=Get-Counter -Counter @('\Memory\Standby Cache Normal Priority Bytes','\Memory\Standby Cache Reserve Bytes','\Memory\Standby Cache Core Bytes') -ErrorAction Stop
  foreach($s in $c.CounterSamples){$standby += [int64]($s.CookedValue/1024)}
 } catch { $standby=0 }
 $available=[Math]::Min($total,($free+$standby))
 [pscustomobject]@{TotalKB=$total;FreeKB=$free;CacheKB=$standby;AvailableKB=$available;UsedKB=($total-$available);AvailablePct=[Math]::Round(($available*100.0/$total),1)}
}
function GiB([int64]$kb){ "{0:N1} GiB" -f ($kb/1048576.0) }
function Show-Status($m){
 "Total:      $(GiB $m.TotalKB)"
 "Used:       $(GiB $m.UsedKB)"
 "Available:  $(GiB $m.AvailableKB) ($($m.AvailablePct)%)"
 "  Free:     $(GiB $m.FreeKB)"
 "  Standby cache estimate: $(GiB $m.CacheKB)"
}
function Add-Sample($m){
 New-Item -ItemType Directory -Force -Path $StateDir|Out-Null
 $r=[pscustomobject]@{timestamp=(Get-Date -Format "yyyy-MM-ddTHH:mm:ssK");total_kb=$m.TotalKB;used_kb=$m.UsedKB;available_kb=$m.AvailableKB;available_pct=$m.AvailablePct}
 if(Test-Path $LogPath){$r|Export-Csv -Path $LogPath -NoTypeInformation -Append}else{$r|Export-Csv -Path $LogPath -NoTypeInformation}
 if((Get-Item $LogPath).Length -gt 10MB){$h=Get-Content $LogPath -TotalCount 1;$tail=Get-Content $LogPath|Select-Object -Skip 1 -Last 50000;@($h)+@($tail)|Set-Content -Path $LogPath -Encoding UTF8}
}
function Send-Report($m){
 $server=$env:RAM_ALTMAN_SMTP_SERVER
 if(-not $server){throw "Set RAM_ALTMAN_SMTP_SERVER to send email."}
 $port=587;if($env:RAM_ALTMAN_SMTP_PORT){$port=[int]$env:RAM_ALTMAN_SMTP_PORT}
 $smtp=$null;$message=New-Object System.Net.Mail.MailMessage
 try{
  if($SenderName){$message.From=New-Object System.Net.Mail.MailAddress -ArgumentList $Sender,$SenderName}else{$message.From=$Sender}
  $message.To.Add($Recipient);$message.Subject="Unused RAM detected on my Windows PC"
  $display=if($SenderName){$SenderName}else{"A concerned RAM owner"}
  $message.Body=@"
Hi Sam,

This Windows PC has $(GiB $m.TotalKB) of RAM installed and $(GiB $m.AvailableKB) ($($m.AvailablePct)%) is currently available.

The estimate adds free physical memory and standby cache counters when available. Windows performance counter names are localized; if they cannot be read, only free physical memory is counted.

Hoarding responsibly,
$display

--
Sent automatically, at most once a day, by a small script on one PC.
Reply if you'd like it to stop.
"@
  $smtp=New-Object System.Net.Mail.SmtpClient($server,$port)
  $smtp.EnableSsl=($env:RAM_ALTMAN_SMTP_SSL -ne "false")
  if($env:RAM_ALTMAN_SMTP_USERNAME){
   if(-not $env:RAM_ALTMAN_SMTP_PASSWORD){throw "Set RAM_ALTMAN_SMTP_PASSWORD when SMTP username is set."}
   $smtp.Credentials=New-Object System.Net.NetworkCredential($env:RAM_ALTMAN_SMTP_USERNAME,$env:RAM_ALTMAN_SMTP_PASSWORD)
  }else{$smtp.UseDefaultCredentials=$false}
  $smtp.Send($message)
 }finally{$message.Dispose();if($smtp){$smtp.Dispose()}}
}
if($Action -in @("--help","-h","/?")){Write-Output "Usage: ram-altman.bat [--status|--dry-run|--help]";exit 0}
$m=Get-Memory
if($Action -eq "--status"){Show-Status $m;exit 0}
if($Action -eq "--dry-run"){
 Show-Status $m
 if($m.AvailableKB*100 -le $Threshold*$m.TotalKB){Write-Output "No email: available RAM is not above $Threshold%.";exit 0}
 $to=if($Recipient){$Recipient}else{"recipient-not-set@example.com"};$from=if($Sender){$Sender}else{"sender-not-set@example.com"}
 Write-Output "";Write-Output "From: $from";Write-Output "To: $to";Write-Output "Subject: Unused RAM detected on my Windows PC";Write-Output ""
 Write-Output "Hi Sam,";Write-Output "";Write-Output "This PC has $(GiB $m.TotalKB) of RAM and $(GiB $m.AvailableKB) ($($m.AvailablePct)%) is currently available.";Write-Output "";Write-Output "Hoarding responsibly,";Write-Output $(if($SenderName){$SenderName}else{"A concerned RAM owner"})
 exit 0
}
if($Action){throw "Unknown option: $Action (try --help)"}
if(-not $Recipient){throw "Set RAM_ALTMAN_TO."};if(-not $Sender){throw "Set RAM_ALTMAN_FROM."}
New-Item -ItemType Directory -Force -Path $StateDir|Out-Null
$lockPath=Join-Path $StateDir "run.lock";$lock=$null
try{
 try{$lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{exit 0}
 Add-Sample $m
 if($m.AvailableKB*100 -le $Threshold*$m.TotalKB){exit 0}
 $today=Get-Date -Format "yyyy-MM-dd"
 if((Test-Path $LastPath)-and((Get-Content $LastPath -Raw).Trim() -eq $today)){exit 0}
 Send-Report $m
 Set-Content -Path $LastPath -Value $today -NoNewline
}finally{if($lock){$lock.Dispose()}}
