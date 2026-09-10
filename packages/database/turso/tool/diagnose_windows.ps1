param([Parameter(Mandatory)][string]$Bundle)

$ErrorActionPreference = 'Stop'
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' |
  Select-Object ProductName, InstallationType, CurrentBuild | Format-List

$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$dumpbin = & $vswhere -latest -products '*' -find 'VC\Tools\MSVC\**\bin\Hostx64\x64\dumpbin.exe' |
  Select-Object -First 1
if (-not $dumpbin) { throw 'Cannot locate x64 dumpbin in Visual Studio Build Tools.' }

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LoaderProbe {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern IntPtr LoadLibraryW(string path);
  [DllImport("kernel32.dll")]
  public static extern bool FreeLibrary(IntPtr module);
  [DllImport("kernel32.dll")]
  public static extern uint SetErrorMode(uint mode);
}
'@
[void][LoaderProbe]::SetErrorMode(0x8001)
$env:PATH = "$Bundle;$env:PATH"
$dependencies = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($binary in Get-ChildItem $Bundle -File | Where-Object { $_.Extension -in '.exe', '.dll' }) {
  Write-Host "Dependencies of $($binary.Name):"
  $table = & $dumpbin /DEPENDENTS $binary.FullName
  if ($LASTEXITCODE -ne 0) { throw "dumpbin failed for $($binary.Name)." }
  foreach ($line in $table) {
    if ($line -match '^\s+(\S+\.dll)\s*$') {
      Write-Host "  $($Matches[1])"
      [void]$dependencies.Add($Matches[1])
    }
  }
}
foreach ($dependency in $dependencies) {
  $local = Join-Path $Bundle $dependency
  $target = if (Test-Path $local) { $local } else { $dependency }
  $module = [LoaderProbe]::LoadLibraryW($target)
  if ($module -eq [IntPtr]::Zero) {
    $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Host "LOAD FAILED: $dependency (Win32 error $code)"
  } else {
    Write-Host "LOAD OK: $dependency"
    [void][LoaderProbe]::FreeLibrary($module)
  }
}
