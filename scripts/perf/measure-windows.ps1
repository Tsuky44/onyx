<#
.SYNOPSIS
  Mesure la RAM et le CPU de l'app Windows d'Onyx, scénario par scénario.

.DESCRIPTION
  Ligne de base des optimisations RAM/CPU : sans chiffres d'avant, aucun gain
  ne se prouve. Le script lance (ou rejoint) `app.exe`, puis échantillonne
  chaque seconde la mémoire privée (ce que l'app a vraiment alloué, ce que
  Windows ne peut pas reprendre sans la tuer), l'ensemble de travail (ce qui
  est en RAM physique à l'instant) et la part de CPU de toute la machine,
  comme le Gestionnaire des tâches.

  Trois scénarios passent seuls :
    - accueil      : l'app au premier plan, sans y toucher ;
    - arriere-plan : fenêtre visible mais sans le focus (état `inactive` de
                     Flutter), comme derrière un navigateur ;
    - reduite      : fenêtre réduite dans la barre des tâches (`hidden`).
  Deux autres demandent la main, avec -Guided : défilement d'une grosse
  bibliothèque, puis lecture d'un film (4K si possible).

  Chaque échantillon note si la fenêtre avait vraiment le focus : Windows
  peut refuser le premier plan à un processus lancé par un script, et un
  « accueil » mesuré sans focus ne dit pas la même chose.

  Lancer une build release ou profile, jamais debug (le JIT et les outils de
  débogage faussent tout), avec STORE_BUILD=true pour couper la mise à jour
  automatique.

.EXAMPLE
  .\scripts\perf\measure-windows.ps1 -Exe app\build\windows\x64\runner\Release\app.exe -Label avant

.EXAMPLE
  .\scripts\perf\measure-windows.ps1 -Attach -Guided -Label apres -Baseline perf-out\avant\summary.csv
#>
[CmdletBinding()]
param(
  # Chemin de app.exe à lancer. Sans -Exe, -Attach rejoint un app.exe déjà ouvert.
  [string]$Exe,
  [switch]$Attach,
  [string]$ProcessName = 'app',
  # Nom de la série, utilisé pour le dossier de sortie.
  [string]$Label = (Get-Date -Format 'yyyyMMdd-HHmmss'),
  [string]$OutDir = 'perf-out',
  # Durée de chaque scénario, en secondes.
  [int]$Seconds = 60,
  # Attente après le lancement : l'accueil charge ses rangées et ses images.
  [int]$Warmup = 25,
  [switch]$Guided,
  # summary.csv d'une série précédente, pour afficher les écarts.
  [string]$Baseline,
  # Laisse l'app ouverte à la fin (sinon elle est fermée si le script l'a lancée).
  [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'

Add-Type -Namespace OnyxPerf -Name Win32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr hWnd);
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool IsIconic(System.IntPtr hWnd);
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, System.UIntPtr extra);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern System.IntPtr FindWindow(string cls, string title);
'@

$SW_MINIMIZE = 6
$SW_RESTORE = 9
$cores = [Environment]::ProcessorCount

# Windows refuse le premier plan à un processus qui ne l'a pas : une pression
# d'Alt simulée lève ce verrou le temps d'un appel.
function Set-Foreground([IntPtr]$target) {
  for ($try = 0; $try -lt 5; $try++) {
    [OnyxPerf.Win32]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
    [void][OnyxPerf.Win32]::SetForegroundWindow($target)
    [OnyxPerf.Win32]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
    if ([OnyxPerf.Win32]::GetForegroundWindow() -eq $target) { return }
  }
  Write-Warning "Premier plan refusé : la colonne focusedPct le dira."
}

function Get-OnyxProcess {
  if ($Exe) {
    $path = (Resolve-Path $Exe).Path
    Write-Host "Lancement de $path"
    $p = Start-Process -FilePath $path -WorkingDirectory (Split-Path $path) -PassThru
    $script:launched = $true
    return $p
  }
  if (-not $Attach) { throw 'Donner -Exe <chemin de app.exe> ou -Attach.' }
  $found = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
  if ($found.Count -eq 0) { throw "Aucun processus '$ProcessName' ouvert." }
  if ($found.Count -gt 1) { throw "Plusieurs '$ProcessName' ouverts : en garder un seul." }
  return $found[0]
}

function Wait-MainWindow($proc) {
  for ($i = 0; $i -lt 60; $i++) {
    $proc.Refresh()
    if ($proc.HasExited) { throw "L'app s'est fermée au démarrage (code $($proc.ExitCode))." }
    if ($proc.MainWindowHandle -ne [IntPtr]::Zero) { return $proc.MainWindowHandle }
    Start-Sleep -Milliseconds 500
  }
  throw "La fenêtre de l'app n'est pas apparue en 30 s."
}

function Measure-Scenario($proc, $hwnd, [string]$name) {
  Write-Host ("  {0,-14} {1} s..." -f $name, $Seconds)
  $samples = New-Object System.Collections.Generic.List[object]
  $proc.Refresh()
  $lastCpu = $proc.TotalProcessorTime.TotalSeconds
  $lastAt = [Diagnostics.Stopwatch]::StartNew()
  for ($i = 0; $i -lt $Seconds; $i++) {
    Start-Sleep -Seconds 1
    $proc.Refresh()
    if ($proc.HasExited) { throw "L'app s'est fermée pendant « $name »." }
    $cpu = $proc.TotalProcessorTime.TotalSeconds
    $elapsed = $lastAt.Elapsed.TotalSeconds
    $lastAt.Restart()
    $samples.Add([pscustomobject]@{
        scenario  = $name
        t         = $i + 1
        cpuPct    = [math]::Round(($cpu - $lastCpu) / $elapsed / $cores * 100, 2)
        privateMB = [math]::Round($proc.PrivateMemorySize64 / 1MB, 1)
        workingMB = [math]::Round($proc.WorkingSet64 / 1MB, 1)
        threads   = $proc.Threads.Count
        focused   = ([OnyxPerf.Win32]::GetForegroundWindow() -eq $hwnd)
        minimized = [OnyxPerf.Win32]::IsIconic($hwnd)
      })
    $lastCpu = $cpu
  }
  return $samples
}

function Get-Percentile($values, [double]$p) {
  $sorted = @($values | Sort-Object)
  if ($sorted.Count -eq 0) { return 0 }
  $index = [math]::Min($sorted.Count - 1, [math]::Ceiling($p * $sorted.Count) - 1)
  return $sorted[[math]::Max(0, $index)]
}

function Get-Summary($samples) {
  $samples | Group-Object scenario | ForEach-Object {
    $s = $_.Group
    $cpu = $s | ForEach-Object cpuPct
    $priv = $s | ForEach-Object privateMB
    $focusedShare = @($s | Where-Object focused).Count / $s.Count
    $minimizedShare = @($s | Where-Object minimized).Count / $s.Count
    [pscustomobject]@{
      scenario       = $_.Name
      cpuAvgPct      = [math]::Round(($cpu | Measure-Object -Average).Average, 2)
      cpuP95Pct      = Get-Percentile $cpu 0.95
      privateEndMB   = $priv[-1]
      privateMaxMB   = ($priv | Measure-Object -Maximum).Maximum
      workingAvgMB   = [math]::Round(($s | ForEach-Object workingMB | Measure-Object -Average).Average, 1)
      threads        = $s[-1].threads
      focusedPct     = [math]::Round($focusedShare * 100)
      minimizedPct   = [math]::Round($minimizedShare * 100)
    }
  }
}

$script:launched = $false
$proc = Get-OnyxProcess
$hwnd = Wait-MainWindow $proc
Write-Host "PID $($proc.Id), $cores processeurs logiques. Échauffement $Warmup s..."
Set-Foreground $hwnd
Start-Sleep -Seconds $Warmup

$all = New-Object System.Collections.Generic.List[object]
try {
  [void][OnyxPerf.Win32]::ShowWindow($hwnd, $SW_RESTORE)
  Set-Foreground $hwnd
  Start-Sleep -Seconds 2
  $all.AddRange((Measure-Scenario $proc $hwnd 'accueil'))

  # Le focus passe à la barre des tâches : la fenêtre reste visible, sans le
  # focus, comme derrière un navigateur, sans rien poser par-dessus.
  Set-Foreground ([OnyxPerf.Win32]::FindWindow('Shell_TrayWnd', $null))
  Start-Sleep -Seconds 2
  $all.AddRange((Measure-Scenario $proc $hwnd 'arriere-plan'))

  [void][OnyxPerf.Win32]::ShowWindow($hwnd, $SW_MINIMIZE)
  Start-Sleep -Seconds 2
  $all.AddRange((Measure-Scenario $proc $hwnd 'reduite'))

  [void][OnyxPerf.Win32]::ShowWindow($hwnd, $SW_RESTORE)
  Set-Foreground $hwnd

  if ($Guided) {
    Read-Host "`nOuvre une grosse bibliothèque. Entrée, puis fais défiler sans t'arrêter pendant $Seconds s"
    $all.AddRange((Measure-Scenario $proc $hwnd 'defilement'))
    Read-Host "`nLance un film (4K si possible) et laisse-le jouer. Entrée quand l'image tourne"
    $all.AddRange((Measure-Scenario $proc $hwnd 'lecture'))
    Read-Host "`nQuitte le lecteur et reviens à l'accueil. Entrée quand c'est fait"
    Start-Sleep -Seconds 5
    $all.AddRange((Measure-Scenario $proc $hwnd 'apres-lecture'))
  }
}
finally {
  $dir = Join-Path $OutDir $Label
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $all | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $dir 'samples.csv')
  $summary = @(Get-Summary $all)
  $summary | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $dir 'summary.csv')
  if ($script:launched -and -not $KeepOpen -and -not $proc.HasExited) {
    $proc.CloseMainWindow() | Out-Null
    if (-not $proc.WaitForExit(5000)) { $proc.Kill() }
  }
}

Write-Host "`nRésultats : $dir"
$summary | Format-Table -AutoSize | Out-String | Write-Host

if ($Baseline) {
  $before = @{}
  Import-Csv $Baseline | ForEach-Object { $before[$_.scenario] = $_ }
  Write-Host 'Écart avec la ligne de base (négatif = mieux) :'
  # Export-Csv écrit les nombres dans la langue du système (« 0,42 » en
  # français) : un simple [double] les relirait comme 42.
  $culture = [Globalization.CultureInfo]::CurrentCulture
  function ConvertTo-Number($text) { [double]::Parse($text, $culture) }
  $summary | ForEach-Object {
    $b = $before[$_.scenario]
    if (-not $b) { return }
    [pscustomobject]@{
      scenario       = $_.scenario
      cpuAvgPct      = [math]::Round($_.cpuAvgPct - (ConvertTo-Number $b.cpuAvgPct), 2)
      privateEndMB   = [math]::Round($_.privateEndMB - (ConvertTo-Number $b.privateEndMB), 1)
      privateMaxMB   = [math]::Round($_.privateMaxMB - (ConvertTo-Number $b.privateMaxMB), 1)
    }
  } | Format-Table -AutoSize | Out-String | Write-Host
}
