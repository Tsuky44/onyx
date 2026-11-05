// Les types du contrat de parité (docs/agents/native-tv-parity.md, §3.2) que
// `onyx_apple_player.dart` n'exporte pas encore : le contrat est figé pour
// les lots, alors l'app les prend ici, à un seul endroit. À retirer dès que le
// paquet les exporte lui-même ; une double exportation de la même classe ne
// casse rien entre-temps.
// ignore_for_file: implementation_imports
export 'package:onyx_player_apple/src/messages.g.dart'
    show
        OnyxAppleNativeChapter,
        OnyxAppleNativeNextUp,
        OnyxAppleNativePanel,
        OnyxAppleNativePanelRow,
        OnyxAppleNativePrompt;
