#requires -Version 7.0
<#
.SYNOPSIS
    Installs the Windows cat cam MSI the way a user does and checks what it promises; inside :winamd64, as admin.
.DESCRIPTION
    Each check prints PASS or FAIL; the exit code is the number of failures. The installed exe runs with a scrubbed
    environment (System32 on PATH, no GST_*, ORT_* or KATAGLYPHIS_*) and must load every module from its install
    folder or Windows itself, idle and while a webrtcsrc viewer decodes its stream.
.PARAMETER Msi
    The omni-accelerant-catcam-<version>-windows-<arch>.msi to test; a wildcard naming exactly one file works too.
.PARAMETER Photo
    A photo with a cat in it, for the model check.
#>
param(
    [Parameter(Mandatory)][string]$Msi,
    [Parameter(Mandatory)][string]$Photo
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$product = 'OmniAccelerANT Cat Cam'
$prefix = Join-Path $env:ProgramFiles $product
$exe = Join-Path $prefix 'kataglyphis_cat_webrtc.exe'
$startup = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\StartUp\$product.lnk"
$work = Join-Path $env:TEMP "catcam-test-$PID"
$null = New-Item -ItemType Directory -Force -Path $work
$script:failures = 0
$msis = @(Get-ChildItem -Path $Msi -File)
if ($msis.Count -ne 1) { throw "-Msi must name exactly one MSI; $Msi matches $($msis.Count)" }
$Msi = $msis[0].FullName
# A wildcard is fine, and the copy has a plain name: an & in a path splits cmd's command line, which docker run goes through.
$source = Get-ChildItem -Path $Photo -File | Select-Object -First 1
if (-not $source) { throw "no photo at $Photo" }
$Photo = Join-Path $work "cat$($source.Extension)"
Copy-Item -LiteralPath $source.FullName -Destination $Photo

function Test-Check {
    param([string]$Name, [scriptblock]$Condition)
    $ok = try { [bool](& $Condition) } catch { Write-Host "      $($_.Exception.Message)"; $false }
    if ($ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name"; $script:failures++ }
}

# The environment a fresh logon gives a process, and nothing of the image's.
function Start-Installed {
    param([string[]]$Arguments, [string]$LogName)
    $psi = [System.Diagnostics.ProcessStartInfo]::new($exe)
    foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardOutput = $true
    $psi.WorkingDirectory = $prefix
    $psi.Environment.Clear()
    foreach ($name in 'SystemRoot', 'SystemDrive', 'windir', 'TEMP', 'TMP', 'USERPROFILE', 'LOCALAPPDATA', 'APPDATA', 'ProgramData', 'ProgramFiles', 'COMPUTERNAME', 'USERNAME') {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) { $psi.Environment[$name] = $value }
    }
    $psi.Environment['PATH'] = "$env:SystemRoot\System32;$env:SystemRoot"
    $proc = [System.Diagnostics.Process]::Start($psi)
    $log = Join-Path $work $LogName
    $null = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action { Add-Content -LiteralPath $Event.MessageData -Value $EventArgs.Data } -MessageData $log
    $proc.BeginErrorReadLine()
    $proc.BeginOutputReadLine()
    [pscustomobject]@{ Process = $proc; Log = $log }
}

function Get-ForeignModule {
    param([System.Diagnostics.Process]$Process)
    $Process.Refresh()
    @($Process.Modules | ForEach-Object FileName | Where-Object {
            -not $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and
            -not $_.StartsWith($env:SystemRoot, [StringComparison]::OrdinalIgnoreCase)
        })
}

# Rows of the MSI's own tables, through the Windows Installer COM API, read-only.
function Get-MsiRow {
    param([string]$Path, [string]$Query)
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $db = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($Path, 0))
    $view = $db.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $db, @($Query))
    $null = $view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null)
    try {
        while ($record = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)) {
            $count = $record.GetType().InvokeMember('FieldCount', 'GetProperty', $null, $record, $null)
            , @(1..$count | ForEach-Object { $record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, $_) })
        }
    } finally {
        $null = $view.GetType().InvokeMember('Close', 'InvokeMethod', $null, $view, $null)
        $null = [Runtime.InteropServices.Marshal]::ReleaseComObject($view)
        $null = [Runtime.InteropServices.Marshal]::ReleaseComObject($db)
    }
}

# Inbound allow rules bound to the installed exe; empty where Windows Firewall is off.
function Get-ExeFirewallRule {
    @(Get-NetFirewallApplicationFilter -Program $exe -ErrorAction SilentlyContinue | Get-NetFirewallRule |
            Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' })
}

function Wait-Healthz {
    $deadline = (Get-Date).AddSeconds(40)
    do {
        $body = try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 http://127.0.0.1:8080/healthz).Content } catch { $null }
        if ($body) { return $body }
        Start-Sleep -Milliseconds 500
    } until ((Get-Date) -gt $deadline)
    return $null
}

Write-Host '=== install ==='
Test-Check 'the MSI opens the firewall to the local subnet for its exe, and installs where it cannot' {
    $rows = @(Get-MsiRow -Path $Msi -Query 'SELECT `Program`, `RemoteAddresses`, `Attributes` FROM `Wix5FirewallException`')
    $rows.Count -eq 1 -and $rows[0][0] -eq '[#exe0]' -and $rows[0][1] -eq 'LocalSubnet' -and ([int]$rows[0][2] -band 1)
}
# A container has no firewall service; the MSI then skips the rule, and only a host can show it.
$firewallOn = (Get-Service MpsSvc -ErrorAction SilentlyContinue).Status -eq 'Running'
$installLog = Join-Path $work 'install.log'
$p = Start-Process msiexec.exe -ArgumentList '/i', "`"$Msi`"", '/qn', '/l*v', "`"$installLog`"" -Wait -PassThru
Test-Check 'msiexec installs it silently' { $p.ExitCode -eq 0 }
Test-Check 'the exe, its plugins, the model and the page are installed' {
    (Test-Path $exe) -and (Test-Path (Join-Path $prefix 'lib\gstreamer-1.0\gstrswebrtc.dll')) -and
    (Test-Path (Join-Path $prefix 'models\yolo26n.onnx')) -and (Test-Path (Join-Path $prefix 'web\index.html')) -and
    (Test-Path (Join-Path $prefix 'onnxruntime.dll'))
}
Test-Check 'the all-users Startup folder starts it at logon' { Test-Path $startup }
Test-Check 'the Start menu has Cat Cam and its page' {
    Test-Path (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\$product\Cat Cam page.lnk")
}
if ($firewallOn) {
    Test-Check 'Windows Firewall lets the local subnet reach the exe' {
        $rules = @(Get-ExeFirewallRule)
        $rules.Count -gt 0 -and @($rules | Get-NetFirewallAddressFilter | Where-Object { $_.RemoteAddress -contains 'LocalSubnet' }).Count -gt 0
    }
} else { Write-Host 'SKIP  the firewall rule itself: this Windows runs no firewall service' }

Write-Host '=== the installed service, scrubbed environment ==='
$svc = Start-Installed -Arguments @('--camera', 'test', '--inference', 'off') -LogName 'service.log'
$health = Wait-Healthz
Write-Host "      healthz: $health"
Test-Check '/healthz answers on :8080' { $health -match '"ok":true' }
Test-Check 'the page is served from the install' { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 http://127.0.0.1:8080/).Content -match '<html' }
$foreign = @(Get-ForeignModule -Process $svc.Process)
if ($foreign) { Write-Host "      outside: $($foreign -join ', ')" }
Test-Check 'idle, it loads modules only from the install and Windows' { $foreign.Count -eq 0 }

# The image's GStreamer plays the viewer; only the cat cam side runs from the install.
$viewer = Start-Process gst-launch-1.0 -ArgumentList '-e', 'webrtcsrc', 'signaller::uri=ws://127.0.0.1:8443', 'connect-to-first-producer=true', '!', 'video/x-raw', '!', 'queue', '!', 'identity', 'eos-after=60', '!', 'fakesink' `
    -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $work 'viewer-out.log') -RedirectStandardError (Join-Path $work 'viewer-err.log')
$null = $viewer.Handle
Start-Sleep -Seconds 4
$foreignLive = @(Get-ForeignModule -Process $svc.Process)
if ($foreignLive) { Write-Host "      outside: $($foreignLive -join ', ')" }
Test-Check 'with a viewer, it loads modules only from the install and Windows' { $foreignLive.Count -eq 0 }
$done = $viewer.WaitForExit(90000)
Test-Check 'a webrtcsrc viewer decodes 60 frames from it' {
    $done -and $viewer.ExitCode -eq 0 -and (Select-String -Path (Join-Path $work 'viewer-out.log') -Pattern 'Got EOS' -Quiet)
}
if (-not $done) { $viewer.Kill($true) }
$svc.Process.Kill($true)
$svc.Process.WaitForExit()

Write-Host '=== the bundled model ==='
$infer = Start-Installed -Arguments @('--camera', "image:$Photo", '--inference', 'on', '--fps', '5', '--http-port', '0', '--listen-port', '8453') -LogName 'infer.log'
Start-Sleep -Seconds 25
$infer.Process.Kill($true)
$infer.Process.WaitForExit()
Get-Content -LiteralPath $infer.Log -ErrorAction SilentlyContinue | Select-String -Pattern 'model:|ONNX Runtime loaded|ORT session|ERROR|cat in view' | Select-Object -First 5 | ForEach-Object { Write-Host "      $($_.Line)" }
Test-Check 'it runs its own model on its own ONNX Runtime and finds a cat' {
    $log = Get-Content -LiteralPath $infer.Log -Raw
    $log -match [regex]::Escape("$prefix\models\yolo26n.onnx") -and $log -match [regex]::Escape("$prefix\onnxruntime.dll") -and $log -match 'cat in view'
}

Write-Host '=== uninstall ==='
$u = Start-Process msiexec.exe -ArgumentList '/x', "`"$Msi`"", '/qn' -Wait -PassThru
Test-Check 'msiexec removes it silently' { $u.ExitCode -eq 0 }
Test-Check 'nothing is left: the folder, the Startup entry, the Start menu folder' {
    -not (Test-Path $exe) -and -not (Test-Path $startup) -and -not (Test-Path (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\$product"))
}
if ($firewallOn) { Test-Check 'the firewall rule went with it' { @(Get-ExeFirewallRule).Count -eq 0 } }

Write-Host "$($script:failures) failure(s)"
if ($script:failures -gt 0) {
    foreach ($log in @(Get-ChildItem $work -Filter '*.log' -Exclude 'install.log')) { Write-Host "--- $($log.Name)"; Get-Content $log.FullName -Tail 8 | ForEach-Object { Write-Host $_ } }
}
exit $script:failures
