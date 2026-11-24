# Lance l'app Windows plusieurs fois de suite et compte les arrêts au
# lancement (ADR-0167). À refaire à chaque montée de Flutter, sur une vraie
# machine avec GPU : la 3.50.1 sans protection plantait 2 à 6 fois sur 20 sur
# une RX 6800 XT (flutter/flutter#196618), la 3.44.4 jamais.
#
#   powershell -File tool\windows_launch_stress.ps1 -Exe build\windows\x64\runner\Profile\app.exe
#   powershell -File tool\windows_launch_stress.ps1 -Exe <app.exe> -Skia
#
# Une build profile ou debug : en release, la sortie standard est muette et
# -Skia n'a pas d'effet. Rend 1 si un lancement s'arrête, ou si la ligne
# « protection multithread D3D11 active » du runner manque.
param(
  [Parameter(Mandatory = $true)][string]$Exe,
  [int]$Count = 40,
  [int]$Seconds = 10,
  [switch]$Skia
)

$Exe = (Resolve-Path $Exe).Path
$dir = Split-Path $Exe
$label = if ($Skia) { 'skia' } else { 'defaut' }
Remove-Item Env:FLUTTER_ENGINE_SWITCHES, Env:FLUTTER_ENGINE_SWITCH_1 -ErrorAction SilentlyContinue
if ($Skia) {
  $env:FLUTTER_ENGINE_SWITCHES = 1
  $env:FLUTTER_ENGINE_SWITCH_1 = 'enable-impeller=false'
}
$dumps = Join-Path $env:LOCALAPPDATA 'CrashDumps'
$before = Get-Date
$crashes = 0
$unprotected = 0
try {
  for ($i = 1; $i -le $Count; $i++) {
    $out = Join-Path $env:TEMP "onyx-launch-$label-$i.out"
    $p = Start-Process -FilePath $Exe -WorkingDirectory $dir `
      -RedirectStandardOutput $out -RedirectStandardError "$out.err" -PassThru
    Start-Sleep $Seconds
    $protected = Select-String -Path $out -Pattern 'protection multithread D3D11 active' -Quiet
    if (-not $protected) { $unprotected++ }
    if ($p.HasExited) {
      $crashes++
      "essai $i : arrêt, code 0x{0:X}, protection {1}" -f $p.ExitCode, $(if ($protected) { 'oui' } else { 'non' })
    } else {
      Stop-Process -Id $p.Id -Force
      $p.WaitForExit()
      "essai $i : vivant, protection {0}" -f $(if ($protected) { 'oui' } else { 'non' })
    }
    Start-Sleep 2
  }
} finally {
  Remove-Item Env:FLUTTER_ENGINE_SWITCHES, Env:FLUTTER_ENGINE_SWITCH_1 -ErrorAction SilentlyContinue
}

"$label : $crashes arrêts sur $Count, $unprotected lancements sans protection"
if (Test-Path $dumps) {
  Get-ChildItem $dumps -Filter 'app.exe.*.dmp' |
    Where-Object { $_.LastWriteTime -ge $before } |
    ForEach-Object { "vidage : $($_.FullName)" }
}
if ($crashes -gt 0 -or $unprotected -gt 0) { exit 1 }
exit 0
