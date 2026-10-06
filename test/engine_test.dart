import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:connections_game/models/dimension.dart';
import 'package:connections_game/models/entity.dart';
import 'package:connections_game/providers/engine_provider.dart';
import 'package:connections_game/services/content_repository.dart';
import 'package:connections_game/services/media.dart';

/// Real data + a media resolver built from the real Assets folder (what the asset
/// manifest would list), so these tests exercise the game as shipped.
late List<Entity> entities;
late DimensionRegistry registry;
late MediaResolver media;

ContentRepository repoWithSeed(int seed) => ContentRepository.fromData(
    entities, registry,
    random: Random(seed), media: media);

SubmitResult play(EngineProvider g, List<Entity> items) {
  for (final e in items) {
    g.toggle(e);
  }
  return g.submit();
}

void main() {
  setUpAll(() {
    entities = ((jsonDecode(File('Assets/data/animals/entities.json').readAsStringSync())
            as Map)['entities'] as List)
        .map((e) => Entity.fromJson(e as Map<String, dynamic>))
        .toList();
    registry = DimensionRegistry.fromJson(jsonDecode(
            File('Assets/data/animals/dimensions.json').readAsStringSync())
        as Map<String, dynamic>);
    final assets = Directory('Assets')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll('\\', '/'))
        .toSet();
    media = MediaResolver(assets);
  });

  test('every animal name is capitalised', () {
    final lower = entities.where((e) => e.name[0] != e.name[0].toUpperCase());
    expect(lower.map((e) => e.name), isEmpty);
  });

  for (final seed in [1, 2, 3, 4, 5]) {
    test('every board sorts by one named rule (seed $seed)', () async {
      final repo = repoWithSeed(seed);
      final g = EngineProvider(repo: repo, random: Random(seed));
      await g.init();

      for (int n = 0; n < 3; n++) {
        final b = g.board!;
        expect(b.dimension.id, 'category');
        expect(g.prompt, b.dimension.question);
        expect(b.groups.every((grp) => grp.dimId == 'category'), isTrue);

        // No picture/text style mix that could give a group away.
        expect(b.tiles.where((e) => !media.hasPicture(e)).map((e) => e.name), isEmpty,
            reason: 'every tile on a root board should have a picture');

        for (int i = 0; i < 4; i++) {
          expect(play(g, b.groups[i].items),
              i < 3 ? SubmitResult.correct : SubmitResult.roundDone);
        }
        expect(g.boardFinished, isTrue);
        expect(g.message, 'Solved!');
        expect(g.stars, 3);
        g.newBoard();
      }
    });
  }

  test('near-misses are spotted and count as a mistake', () async {
    final repo = repoWithSeed(11);
    final g = EngineProvider(repo: repo, random: Random(11));
    await g.init();
    final groups = g.board!.groups;

    expect(play(g, groups[0].items), SubmitResult.correct);

    // 3 from one group + 1 from another = one away.
    final nearMiss = [...groups[1].items.take(3), groups[2].items.first];
    expect(play(g, nearMiss), SubmitResult.oneAway);
    expect(g.mistakes, 1);
    expect(g.selected, isEmpty);
  });

  test('root board keeps dinosaurs in play and digs deeper only where possible',
      () async {
    final repo = repoWithSeed(3);
    final g = EngineProvider(repo: repo, random: Random(3));
    await g.init();
    final dino = g.board!.groups.where((x) => x.value == 'dinosaur');
    expect(dino, hasLength(1), reason: 'normal root boards keep dinosaurs in play');

    // Can't dig deeper before the board is solved.
    expect(g.canDescend(dino.single), isFalse);
    for (final grp in g.board!.groups) {
      play(g, grp.items);
    }
    expect(g.boardFinished, isTrue);
    expect(g.canDescend(dino.single), isTrue);
    for (final other in g.board!.groups.where((x) => x.value != 'dinosaur')) {
      expect(g.canDescend(other), isFalse,
          reason: '${other.label} has no deeper 4×4, so no "dig deeper"');
    }

    g.descendInto(dino.single);
    expect(g.pathLabels, ['Animals', 'Dinosaurs']);
    expect(g.board!.dimension.id, 'dino_kind');
    expect(g.atFloor, isFalse);

    g.back();
    expect(g.atRoot, isTrue);
  });
}
