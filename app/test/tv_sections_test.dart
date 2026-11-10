import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/nav/tv_focusable.dart';
import 'package:onyx/tv/nav/tv_region.dart';

import 'support/tv_nav_harness.dart';

String? _focused() {
  final node = FocusManager.instance.primaryFocus;
  return node == null ? null : focusedLabelOf(node);
}

void main() {
  TvNavHarness.forEachEngine((engine) {
    testWidgets(
      '[$engine] les zones verticales passent d’une section à la suivante au bord',
      (tester) async {
        final heroNode = FocusNode(debugLabel: 'Reprendre');
        final season1Node = FocusNode(debugLabel: 'Saison 1');
        final season2Node = FocusNode(debugLabel: 'Saison 2');
        final watchedNode = FocusNode(debugLabel: 'Marquer vue');
        final ep1Node = FocusNode(debugLabel: 'Épisode 1');
        final ep2Node = FocusNode(debugLabel: 'Épisode 2');

        addTearDown(() {
          heroNode.dispose();
          season1Node.dispose();
          season2Node.dispose();
          watchedNode.dispose();
          ep1Node.dispose();
          ep2Node.dispose();
        });

        final nav = await TvNavHarness.pump(
          tester,
          TvRegion.sections(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section 1 : En-tête / Actions (décalé à x = 300 par l'affiche)
                  TvRegion.section(
                    id: 'hero',
                    child: Padding(
                      padding:
                          const EdgeInsets.only(left: 300, top: 40, bottom: 20),
                      child: Row(
                        children: [
                          TvFocusable(
                            focusNode: heroNode,
                            autofocus: true,
                            onSelect: () {},
                            child: const Text('Reprendre'),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Section 2 : Saisons (calé à gauche, x = 48)
                  TvRegion.section(
                    id: 'seasons',
                    child: Padding(
                      padding:
                          const EdgeInsets.only(left: 48, top: 20, bottom: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              TvFocusable(
                                focusNode: season1Node,
                                entry: true,
                                onSelect: () {},
                                child: const Text('Saison 1'),
                              ),
                              const SizedBox(width: 16),
                              TvFocusable(
                                focusNode: season2Node,
                                onSelect: () {},
                                child: const Text('Saison 2'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TvFocusable(
                            focusNode: watchedNode,
                            onSelect: () {},
                            child: const Text('Marquer vue'),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Section 3 : Épisodes (pleine largeur, x = 48 à 1800)
                  TvRegion.section(
                    id: 'episodes',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 48, vertical: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TvFocusable(
                            focusNode: ep1Node,
                            onSelect: () {},
                            child: const SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: Text('Épisode 1'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TvFocusable(
                            focusNode: ep2Node,
                            onSelect: () {},
                            child: const SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: Text('Épisode 2'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          engine: engine,
        );

        // Au départ, « Reprendre » a le focus (à x = 300)
        expect(_focused(), 'Reprendre');

        // Bas depuis « Reprendre » :
        // Même si « Épisode 1 » est dans le faisceau sous x = 300 et « Saison 1 » à x = 48,
        // la navigation passe par la section des saisons au lieu de sauter aux épisodes !
        await nav.press(TraversalDirection.down);
        expect(_focused(), 'Saison 1');

        // Droite reste dans la section saisons sur Saison 2
        await nav.press(TraversalDirection.right);
        expect(_focused(), 'Saison 2');

        // Gauche revient sur Saison 1
        await nav.press(TraversalDirection.left);
        expect(_focused(), 'Saison 1');

        // Bas descend sur l'élément inférieur de la section saisons (« Marquer vue »)
        await nav.press(TraversalDirection.down);
        expect(_focused(), 'Marquer vue');

        // Bas depuis le plus bas de la section saisons passe au plus haut des épisodes
        await nav.press(TraversalDirection.down);
        expect(_focused(), 'Épisode 1');

        // Bas se déplace à l'intérieur de la section épisodes
        await nav.press(TraversalDirection.down);
        expect(_focused(), 'Épisode 2');

        // Haut remonte dans la section épisodes
        await nav.press(TraversalDirection.up);
        expect(_focused(), 'Épisode 1');

        // Haut depuis le plus haut des épisodes remonte dans la section saisons
        await nav.press(TraversalDirection.up);
        expect(_focused(), 'Marquer vue');

        // Haut remonte à la saison
        await nav.press(TraversalDirection.up);
        expect(_focused(), 'Saison 1');

        // Haut depuis la saison remonte à la section en-tête (« Reprendre »)
        await nav.press(TraversalDirection.up);
        expect(_focused(), 'Reprendre');

        // Haut depuis le haut de la première section reste sur place
        await nav.press(TraversalDirection.up);
        expect(_focused(), 'Reprendre');
      },
    );

    testWidgets(
      '[$engine] sans élément intermédiaire, Bas depuis l’en-tête va aux saisons et de là aux épisodes',
      (tester) async {
        final heroNode = FocusNode(debugLabel: 'Reprendre');
        final season1Node = FocusNode(debugLabel: 'Saison 1');
        final ep1Node = FocusNode(debugLabel: 'Épisode 1');

        addTearDown(() {
          heroNode.dispose();
          season1Node.dispose();
          ep1Node.dispose();
        });

        final nav = await TvNavHarness.pump(
          tester,
          TvRegion.sections(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TvRegion.section(
                  id: 'hero',
                  child: Padding(
                    padding:
                        const EdgeInsets.only(left: 300, top: 40, bottom: 20),
                    child: TvFocusable(
                      focusNode: heroNode,
                      autofocus: true,
                      onSelect: () {},
                      child: const Text('Reprendre'),
                    ),
                  ),
                ),
                TvRegion.section(
                  id: 'seasons',
                  child: Padding(
                    padding:
                        const EdgeInsets.only(left: 48, top: 20, bottom: 20),
                    child: TvFocusable(
                      focusNode: season1Node,
                      entry: true,
                      onSelect: () {},
                      child: const Text('Saison 1'),
                    ),
                  ),
                ),
                TvRegion.section(
                  id: 'episodes',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 48, vertical: 20),
                    child: TvFocusable(
                      focusNode: ep1Node,
                      onSelect: () {},
                      child: const SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: Text('Épisode 1'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          engine: engine,
        );

        expect(_focused(), 'Reprendre');

        await nav.press(TraversalDirection.down);
        expect(_focused(), 'Saison 1');

        await nav.press(TraversalDirection.down);
        expect(_focused(), 'Épisode 1');

        // Au bas de la dernière section, Bas reste sur place
        await nav.press(TraversalDirection.down);
        expect(_focused(), 'Épisode 1');

        await nav.press(TraversalDirection.up);
        expect(_focused(), 'Saison 1');

        await nav.press(TraversalDirection.up);
        expect(_focused(), 'Reprendre');
      },
    );
  });
}
