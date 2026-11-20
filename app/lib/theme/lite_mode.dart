import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/device_hardware.dart';
import '../services/player_presence.dart';
import '../utils/app_platform.dart';
import 'frame_budget_watch.dart';

/// Ce que l'utilisateur a choisi. [auto] allège un appareil connu comme
/// faible, et propose de le faire quand les images saccadent ; les deux
/// autres l'imposent.
enum LiteModePreference { auto, on, off }

/// Pourquoi le mode léger est actif, pour le dire dans les réglages.
enum LiteModeReason { none, chosen, hardware }

/// Le mode léger : une interface qui coûte le moins possible au processeur
/// graphique, pour qu'une Apple TV HD, un boîtier Android à 2 Go ou un
/// Raspberry Pi restent fluides — et que le décodeur garde toute la machine
/// pendant un Direct Play.
///
/// Ce qu'il retire : le flou du verre (une copie floutée de l'écran à chaque
/// image), le mouvement géométrique (comme « réduire les animations », les
/// fondus restent), le reflet des squelettes, la dérive de l'aperçu
/// « Reprendre », et une partie du cache d'images décodées. Rien de ce qui se
/// lit ne disparaît. Voir l'ADR-0086.
///
/// Même forme que `TvMode` : un [ValueNotifier] que la racine écoute une fois
/// et republie par [LiteScope].
///
/// Les saccades mesurées ne l'activent plus d'elles-mêmes : elles lèvent
/// [suggestion], et l'app demande (ADR-0141). Mesurée seule, une Apple TV 4K
/// passait en mode léger pour de bon, sans que personne ne l'ait voulu.
abstract final class LiteMode {
  static const String _preferenceKey = 'lite_mode_preference';
  static const String _declinedKey = 'lite_mode_suggestion_declined';

  /// L'ancienne mesure, qui activait le mode léger sans demander. Effacée au
  /// démarrage : l'appareil qu'elle avait jugé est mesuré de nouveau, et on
  /// lui propose le mode léger s'il saccade vraiment.
  static const String _legacyMeasuredKey = 'lite_mode_measured_slow';

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// Vrai quand les images ont saccadé et que l'app doit proposer le mode
  /// léger. Retombe dès que l'utilisateur a répondu.
  static final ValueNotifier<bool> suggestion = ValueNotifier<bool>(false);

  static LiteModePreference _preference = LiteModePreference.auto;
  static bool _hardware = false;
  static bool _declined = false;
  static void Function()? _stopWatch;

  static LiteModePreference get preference => _preference;

  /// Vrai hors d'un arbre de widgets. Dans un arbre, préférer [LiteScope.of]
  /// pour être reconstruit quand le mode change.
  static bool get isLite => enabled.value;

  static LiteModeReason get reason {
    if (!enabled.value) return LiteModeReason.none;
    if (_preference == LiteModePreference.on) return LiteModeReason.chosen;
    return LiteModeReason.hardware;
  }

  /// Décide le mode avant la première image, puis surveille les images si la
  /// décision est encore ouverte.
  static Future<void> initialize() async {
    await DeviceHardware.initialize();
    _hardware = isModestHardware(
      isAndroid: AppPlatform.isAndroid,
      isIOS: AppPlatform.isIOS,
      isTvOS: AppPlatform.isTvOS,
      isWebOS: AppPlatform.isWebOS,
      totalMemoryMb: DeviceHardware.totalMemoryMb,
      isLowRamDevice: DeviceHardware.isLowRamDevice,
      model: DeviceHardware.model,
      processorCount: AppPlatform.processorCount,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_preferenceKey);
      _preference = LiteModePreference.values.firstWhere(
        (value) => value.name == raw,
        orElse: () => LiteModePreference.auto,
      );
      _declined = prefs.getBool(_declinedKey) ?? false;
      await prefs.remove(_legacyMeasuredKey);
    } catch (error) {
      // Préférences illisibles : on reste sur la détection, qui ne dépend
      // de rien de stocké.
      debugPrint('LiteMode: préférences illisibles ($error)');
    }
    _apply();
    debugPrint('LiteMode: ${enabled.value ? 'actif' : 'inactif'} '
        '(${_preference.name}, matériel=$_hardware, refusé=$_declined, '
        '${DeviceHardware.totalMemoryMb}MB, ${DeviceHardware.model}, '
        '${AppPlatform.processorCount} cpu)');
    _watchIfUndecided();
  }

  /// Applique un choix explicite et le garde. Revenir à [LiteModePreference.auto]
  /// oublie un « non » donné à la proposition : l'appareil est jugé de
  /// nouveau.
  static Future<void> setPreference(LiteModePreference preference) async {
    _preference = preference;
    if (preference == LiteModePreference.auto) _declined = false;
    suggestion.value = false;
    _apply();
    _watchIfUndecided();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_preferenceKey, preference.name);
      if (preference == LiteModePreference.auto) {
        await prefs.remove(_declinedKey);
      }
    } catch (error) {
      // Le choix vaut pour cette session ; seul le prochain démarrage
      // l'aura perdu.
      debugPrint('LiteMode: choix non enregistré ($error)');
    }
  }

  /// Appelé par la surveillance des images quand l'interface ne tient pas sa
  /// cadence : lève [suggestion], sans rien changer à l'interface.
  static void noteSustainedJank() {
    if (!_mayAsk) return;
    debugPrint('LiteMode: saccades mesurées, proposition du mode léger');
    suggestion.value = true;
  }

  /// « Passer en mode léger » : un choix comme un autre, que les réglages
  /// montrent ensuite sur « Activé ».
  static Future<void> acceptSuggestion() =>
      setPreference(LiteModePreference.on);

  /// « Garder l'interface complète » : gardé, la question ne revient pas.
  /// Les réglages restent le moyen de changer d'avis.
  static Future<void> declineSuggestion() async {
    _declined = true;
    suggestion.value = false;
    _watchIfUndecided();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_declinedKey, true);
    } catch (error) {
      // Le refus vaut pour cette session ; le prochain démarrage pourra
      // redemander.
      debugPrint('LiteMode: refus non enregistré ($error)');
    }
  }

  /// La fenêtre fermée sans répondre (Retour, clic à côté) : rien n'est
  /// gardé, et la question attend le prochain démarrage — la surveillance
  /// s'est arrêtée en la posant.
  static void dismissSuggestion() {
    suggestion.value = false;
  }

  static void _apply() {
    enabled.value = switch (_preference) {
      LiteModePreference.on => true,
      LiteModePreference.off => false,
      LiteModePreference.auto => _hardware,
    };
  }

  /// Seul [LiteModePreference.auto] demande, et seulement à un appareil
  /// encore complet qui n'a pas déjà dit non.
  static bool get _mayAsk =>
      _preference == LiteModePreference.auto && !enabled.value && !_declined;

  /// La surveillance ne tourne qu'en build de production — une build de
  /// débogage saccade par nature — et seulement tant qu'il reste une question
  /// à poser. Une fois posée, elle s'arrête jusqu'au démarrage suivant.
  static void _watchIfUndecided() {
    if (!_mayAsk) {
      _stopWatch?.call();
      _stopWatch = null;
      return;
    }
    if (!kReleaseMode || _stopWatch != null) return;
    _stopWatch = FrameBudgetWatch.install(
      SchedulerBinding.instance,
      paused: PlayerPresence.isOpen,
      onSustainedJank: () {
        _stopWatch?.call();
        _stopWatch = null;
        noteSustainedJank();
      },
    );
  }

  /// Si le matériel suffit, à lui seul, à décider du mode léger.
  ///
  /// - Un téléviseur LG (ADR-0076) : CanvasKit y dessine en WebGL sur le
  ///   processeur graphique du téléviseur.
  /// - Une Apple TV HD (`AppleTV5,x`, A8) : c'est l'appareil où l'interface
  ///   a été vue ramer. Une Apple TV 4K (A10X et après) garde tout.
  /// - Moins de 2,5 Go de mémoire, ou un Android qui se dit `isLowRamDevice` :
  ///   les clés de streaming, les boîtiers d'entrée de gamme.
  ///
  /// - Un ordinateur à deux processeurs logiques ou moins (Pentium ou Celeron
  ///   double cœur, sans hyper-threading) : sans processeur graphique digne de
  ///   ce nom, Flutter dessine l'interface sur le processeur, et c'est lui
  ///   qui manque (ADR-0101). Un Pentium à quatre fils passe par la mesure.
  ///
  /// Une mémoire inconnue (0) ne décide rien : la mesure des images s'en
  /// charge, et elle couvre aussi ce que la mémoire ne dit pas — un
  /// Raspberry Pi à 4 Go a beaucoup de mémoire et très peu de GPU.
  @visibleForTesting
  static bool isModestHardware({
    required bool isAndroid,
    required bool isIOS,
    required bool isTvOS,
    required bool isWebOS,
    required int totalMemoryMb,
    required bool isLowRamDevice,
    required String model,
    int processorCount = 0,
  }) {
    if (isWebOS) return true;
    if (isTvOS && model.startsWith('AppleTV5,')) return true;
    if (!isAndroid && !isIOS && !isTvOS) {
      return processorCount > 0 && processorCount <= _modestProcessorCount;
    }
    if (isAndroid && isLowRamDevice) return true;
    return totalMemoryMb > 0 && totalMemoryMb < _modestMemoryMb;
  }

  static const int _modestMemoryMb = 2560;
  static const int _modestProcessorCount = 2;

  @visibleForTesting
  static void resetForTest() {
    _stopWatch?.call();
    _stopWatch = null;
    _preference = LiteModePreference.auto;
    _hardware = false;
    _declined = false;
    enabled.value = false;
    suggestion.value = false;
  }
}

/// Publie [LiteMode.enabled] dans l'arbre, comme `TvScope` pour le mode TV.
class LiteScope extends InheritedWidget {
  final bool isLite;

  const LiteScope({super.key, required this.isLite, required super.child});

  /// Faux sans [LiteScope] au-dessus : un test qui monte un widget seul le
  /// voit dans son rendu complet.
  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LiteScope>();
    return scope?.isLite ?? false;
  }

  @override
  bool updateShouldNotify(LiteScope oldWidget) => oldWidget.isLite != isLite;
}
