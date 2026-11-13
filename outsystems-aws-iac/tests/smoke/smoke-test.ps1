<#
.SYNOPSIS
  Post-deployment smoke test for an OutSystems environment on AWS.

.DESCRIPTION
  Runs after `terraform apply` (and after the OutSystems modules are published)
  against the public URL of an environment. Exit code 0 = all checks passed.

  Checks:
    1. HTTP is permanently redirected to HTTPS
    2. TLS 1.0/1.1 are refused, TLS 1.2 is accepted
    3. /ServiceCenter and /LifeTime return 403 from the internet
    4. Each end-user module (default: SingaporeHousingInsights) responds < 400
    5. Security-relevant response headers are present

.EXAMPLE
  ./tests/smoke/smoke-test.ps1 -BaseUrl https://housing.example.com
#>
param(
  [Parameter(Mandatory = $true)] [string] $BaseUrl,
  [string[]] $Modules = @('SingaporeHousingInsights'),
  [int] $TimeoutSec = 30
)

$ErrorActionPreference = 'Stop'
$BaseUrl = $BaseUrl.TrimEnd('/')
$hostName = ([Uri]$BaseUrl).Host
$failures = 0

function Test-Check([string] $Name, [scriptblock] $Body) {
  try {
    $result = & $Body
    if ($result) { Write-Host "[PASS] $Name" -ForegroundColor Green }
    else { Write-Host "[FAIL] $Name" -ForegroundColor Red; $script:failures++ }
  } catch {
    Write-Host "[FAIL] $Name - $($_.Exception.Message)" -ForegroundColor Red
    $script:failures++
  }
}

function Get-StatusCode([string] $Url) {
  $req = [System.Net.HttpWebRequest]::Create($Url)
  $req.AllowAutoRedirect = $false
  $req.Timeout = $TimeoutSec * 1000
  try { $resp = $req.GetResponse() } catch [System.Net.WebException] { $resp = $_.Exception.Response }
  if ($null -eq $resp) { throw "No response from $Url" }
  $code = [int]$resp.StatusCode
  $location = $resp.Headers['Location']
  $headers = $resp.Headers
  $resp.Close()
  return [pscustomobject]@{ Code = $code; Location = $location; Headers = $headers }
}

function Test-TlsVersion([System.Security.Authentication.SslProtocols] $Protocol) {
  $tcp = New-Object System.Net.Sockets.TcpClient($hostName, 443)
  try {
    $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, { $true })
    $ssl.AuthenticateAsClient($hostName, $null, $Protocol, $false)
    return $true
  } catch { return $false } finally { $tcp.Close() }
}

Write-Host "Smoke testing $BaseUrl`n"

Test-Check 'HTTP redirects to HTTPS (301)' {
  $r = Get-StatusCode ("http://$hostName/")
  $r.Code -eq 301 -and $r.Location -like 'https://*'
}

Test-Check 'TLS 1.2 accepted' { Test-TlsVersion ([System.Security.Authentication.SslProtocols]::Tls12) }
Test-Check 'TLS 1.0 refused'  { -not (Test-TlsVersion ([System.Security.Authentication.SslProtocols]::Tls)) }
Test-Check 'TLS 1.1 refused'  { -not (Test-TlsVersion ([System.Security.Authentication.SslProtocols]::Tls11)) }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

foreach ($path in '/ServiceCenter/', '/LifeTime/') {
  Test-Check "$path blocked from internet (403)" { (Get-StatusCode "$BaseUrl$path").Code -eq 403 }
}

foreach ($module in $Modules) {
  Test-Check "Module '$module' is served (< 400)" {
    $r = Get-StatusCode "$BaseUrl/$module/"
    $r.Code -lt 400
  }
}

Test-Check 'No server version disclosure in X-AspNet-Version' {
  $r = Get-StatusCode "$BaseUrl/$($Modules[0])/"
  -not $r.Headers['X-AspNet-Version']
}

Write-Host ''
if ($failures -gt 0) { Write-Host "$failures check(s) failed." -ForegroundColor Red; exit 1 }
Write-Host 'All smoke checks passed.' -ForegroundColor Green
exit 0
