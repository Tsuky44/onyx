# Onyx : vérifie, en la chargeant, que libmpv-2.dll contient ce que l'app attend.
#
# Lancé par CMakeLists.txt à chaque nouvelle extraction de l'archive épinglée,
# et à la main : powershell -File check_libmpv.ps1 -Dll <chemin\libmpv-2.dll>.
# Un libmpv qui perdrait un décodeur ou libcurl ne casse pas le build ni la
# lecture : la piste TrueHD serait muette, le relais de l'ADR-0036 ignoré. C'est
# ici que ça doit échouer, pas chez un utilisateur. Voir l'ADR-0158 (phase 1).
#
# Ce qui est vérifié tient au contenu du build, pas au GPU de la machine : le
# contrôle passe aussi sur une machine de CI sans carte graphique.

param(
  [Parameter(Mandatory = $true)][string]$Dll
)

$ErrorActionPreference = 'Stop'

$dllPath = (Resolve-Path -LiteralPath $Dll).Path

Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class OnyxLibmpvProbe {
  [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
  static extern IntPtr LoadLibraryExW(string path, IntPtr file, uint flags);
  [DllImport("kernel32", CharSet = CharSet.Ansi, ExactSpelling = true)]
  static extern IntPtr GetProcAddress(IntPtr module, string name);

  // Cherche les dépendances de la DLL dans son propre dossier.
  const uint LOAD_WITH_ALTERED_SEARCH_PATH = 0x8;

  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate uint ApiVersionFn();
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr CreateFn();
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int InitFn(IntPtr h);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SetStrFn(IntPtr h, byte[] name, byte[] value);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int LogFn(IntPtr h, byte[] level);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr GetStrFn(IntPtr h, byte[] name);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr WaitFn(IntPtr h, double timeout);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void PtrFn(IntPtr p);

  [StructLayout(LayoutKind.Sequential)]
  struct MpvEvent { public int id; public int error; public ulong reply; public IntPtr data; }
  [StructLayout(LayoutKind.Sequential)]
  struct MpvLogMessage { public IntPtr prefix; public IntPtr level; public IntPtr text; public int logLevel; }

  const int MPV_EVENT_NONE = 0;
  const int MPV_EVENT_LOG_MESSAGE = 2;

  static IntPtr module;

  static T Fn<T>(string name) {
    IntPtr p = GetProcAddress(module, name);
    if (p == IntPtr.Zero) throw new Exception("symbole absent : " + name);
    return (T)(object)Marshal.GetDelegateForFunctionPointer(p, typeof(T));
  }

  static byte[] Z(string s) { return Encoding.UTF8.GetBytes(s + "\0"); }

  static string Utf8(IntPtr p) {
    if (p == IntPtr.Zero) return null;
    int n = 0;
    while (Marshal.ReadByte(p, n) != 0) n++;
    byte[] b = new byte[n];
    Marshal.Copy(p, b, 0, n);
    return Encoding.UTF8.GetString(b);
  }

  // Ce que l'app appelle : media_kit 1.2.6 (lib/src/player/native) et le plugin
  // media_kit_video (rendu OpenGL dans la texture Flutter).
  public static readonly string[] Symbols = {
    "mpv_client_api_version", "mpv_command", "mpv_command_async", "mpv_command_ret",
    "mpv_command_string", "mpv_create", "mpv_error_string", "mpv_free",
    "mpv_free_node_contents", "mpv_get_property", "mpv_get_property_string",
    "mpv_hook_add", "mpv_hook_continue", "mpv_initialize", "mpv_observe_property",
    "mpv_request_log_messages", "mpv_set_option_string", "mpv_set_property",
    "mpv_set_property_async", "mpv_set_property_string", "mpv_set_wakeup_callback",
    "mpv_terminate_destroy", "mpv_unobserve_property", "mpv_wait_event", "mpv_wakeup",
    "mpv_render_context_create", "mpv_render_context_free",
    "mpv_render_context_render", "mpv_render_context_set_update_callback",
  };

  public static Dictionary<string, object> Run(string path) {
    module = LoadLibraryExW(path, IntPtr.Zero, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (module == IntPtr.Zero)
      throw new Exception("chargement impossible (erreur " + Marshal.GetLastWin32Error() + ")");

    var r = new Dictionary<string, object>();
    var missing = new List<string>();
    foreach (var s in Symbols)
      if (GetProcAddress(module, s) == IntPtr.Zero) missing.Add(s);
    r["missingSymbols"] = missing.ToArray();

    r["apiVersion"] = Fn<ApiVersionFn>("mpv_client_api_version")();

    var setOpt = Fn<SetStrFn>("mpv_set_option_string");
    var setProp = Fn<SetStrFn>("mpv_set_property_string");
    var getProp = Fn<GetStrFn>("mpv_get_property_string");
    var free = Fn<PtrFn>("mpv_free");
    var wait = Fn<WaitFn>("mpv_wait_event");

    IntPtr h = Fn<CreateFn>("mpv_create")();
    if (h == IntPtr.Zero) throw new Exception("mpv_create a échoué");
    try {
      setOpt(h, Z("vo"), Z("null"));
      setOpt(h, Z("ao"), Z("null"));
      setOpt(h, Z("load-scripts"), Z("no"));
      int init = Fn<InitFn>("mpv_initialize")(h);
      if (init < 0) throw new Exception("mpv_initialize a échoué (" + init + ")");

      Func<string, string> get = name => {
        IntPtr p = getProp(h, Z(name));
        if (p == IntPtr.Zero) return null;
        string v = Utf8(p);
        free(p);
        return v;
      };
      foreach (var name in new[] { "mpv-version", "ffmpeg-version", "libass-version",
                                   "curl-enabled", "decoder-list" })
        r[name] = get(name);

      // Les listes de décodeurs matériels et de sorties ne sont pas des
      // propriétés : mpv les écrit dans son journal quand on lui demande
      // « help ». Le refus de la valeur est attendu.
      Fn<LogFn>("mpv_request_log_messages")(h, Z("info"));
      foreach (var opt in new[] { "hwdec", "vo", "gpu-api" })
        setProp(h, Z(opt), Z("help"));
      var log = new StringBuilder();
      while (true) {
        var ev = (MpvEvent)Marshal.PtrToStructure(wait(h, 2.0), typeof(MpvEvent));
        if (ev.id == MPV_EVENT_NONE) break;
        if (ev.id != MPV_EVENT_LOG_MESSAGE) continue;
        var msg = (MpvLogMessage)Marshal.PtrToStructure(ev.data, typeof(MpvLogMessage));
        log.Append(Utf8(msg.text));
      }
      r["helpLog"] = log.ToString();
    } finally {
      Fn<PtrFn>("mpv_terminate_destroy")(h);
    }
    return r;
  }
}
'@

$r = [OnyxLibmpvProbe]::Run($dllPath)
$failures = New-Object System.Collections.Generic.List[string]

function Test-Check([bool]$ok, [string]$label) {
  if ($ok) { Write-Output "  ok   $label" } else { Write-Output "  FAIL $label"; $failures.Add($label) }
}

Write-Output "libmpv : $($r['mpv-version']) · FFmpeg $($r['ffmpeg-version'])"

# API cliente 2.x : celle que media_kit 1.2.6 utilise aujourd'hui (shinchiro :
# 2.5). Ses liaisons générées portent un en-tête 1.109, mais n'appellent que des
# fonctions qui existent toujours en 2.x : c'est la présence de chacune qui
# compte, vérifiée juste après.
$api = [uint32]$r['apiVersion']
$major = $api -shr 16
$minor = $api -band 0xffff
Test-Check ($major -eq 2 -and $minor -ge 5) "API cliente $major.$minor (2.5 ou plus, 2.x)"
Test-Check ($r['missingSymbols'].Count -eq 0) "fonctions appelées par media_kit présentes $($r['missingSymbols'] -join ', ')"

# Les décodeurs, par nom de pilote FFmpeg. `decoder-list` ne couvre que l'audio
# et la vidéo : les sous-titres restent à la liste de parité de l'ADR-0158.
$drivers = @{}
foreach ($d in ($r['decoder-list'] | ConvertFrom-Json)) { $drivers[$d.driver] = $true }
foreach ($d in 'truehd', 'dca', 'eac3', 'ac3', 'hevc', 'av1', 'h264', 'vc1', 'mpeg2video', 'flac', 'opus', 'aac') {
  Test-Check $drivers.ContainsKey($d) "décodeur $d"
}

$help = [string]$r['helpLog']
# Le décodage de Windows (ADR-0095) : d3d11va-copy, sur HEVC et AV1.
Test-Check ($help -match 'hevc-d3d11va-copy') 'hwdec d3d11va-copy (HEVC)'
Test-Check ($help -match 'av1-d3d11va-copy') 'hwdec d3d11va-copy (AV1)'
Test-Check ($help -match '(?m)^\s*d3d11va \(hevc-d3d11va\)') 'hwdec d3d11va (sans copie, phase 2)'
# La texture Flutter passe par l'API de rendu ; la fenêtre Dolby Vision 5
# (ADR-0061) par gpu-next, donc libplacebo, en Direct3D 11.
Test-Check ($help -match '(?m)^\s*libmpv\s') 'sortie libmpv (API de rendu)'
Test-Check ($help -match '(?m)^\s*gpu-next\s') 'sortie gpu-next (libplacebo)'
Test-Check ($help -match '(?m)^\s*d3d11\s+d3d11') 'gpu-api d3d11'
Test-Check ([int64]$r['libass-version'] -gt 0) "libass (0x$('{0:x}' -f [int64]$r['libass-version']))"
# Le relais de l'ADR-0036 compte sur libcurl : CONNECT, puis TLS de bout en bout.
Test-Check ($r['curl-enabled'] -eq 'yes') 'flux HTTP par libcurl (curl-enabled)'

if ($failures.Count -gt 0) {
  Write-Output "libmpv-2.dll incomplet : $($failures -join ' ; ')"
  exit 1
}
Write-Output 'libmpv-2.dll conforme.'
