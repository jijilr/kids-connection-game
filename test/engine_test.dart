import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:connections_game/models/dimension.dart';
import 'package:connections_game/models/entity.dart';
import 'package:connections_game/models/game_settings.dart';
import 'package:connections_game/providers/engine_provider.dart';
import 'package:connections_game/services/board_assembler.dart';
import 'package:connections_game/services/content_repository.dart';
import 'package:connections_game/services/media.dart';

/// Real data + a media resolver built from the real Assets folder (what the asset
/// manifest would list), so these tests exercise the game as shipped.
late List<Entity> entities;
late DimensionRegistry registry;
late GameSettings settings;
late MediaResolver media;

Map<String, dynamic> readData(String file) =>
    jsonDecode(File('Assets/data/$file').readAsStringSync()) as Map<String, dynamic>;

ContentRepository repoWithSeed(int seed) =>
    ContentRepository.fromData(entities, registry, settings,
        random: Random(seed), media: media);

Future<EngineProvider> start(int seed, {ContentRepository? repo}) async {
  final g = EngineProvider(repo: repo ?? repoWithSeed(seed), random: Random(seed));
  await g.init();
  return g;
}

SubmitResult play(EngineProvider g, List<Entity> items) {
  for (final e in items) {
    g.toggle(e);
  }
  return g.submit();
}

void solve(EngineProvider g) {
  for (final grp in g.board!.groups) {
    play(g, grp.items);
  }
}

Entity thing(String id) => entities.firstWhere((e) => e.id == id);

void main() {
  setUpAll(() {
    entities = ContentRepository.thingsFromJson(readData('things.json'));
    registry = DimensionRegistry.fromJson(readData('dictionary.json'));
    settings = GameSettings.fromJson(readData('settings.json'));
    final assets = Directory('Assets')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll('\\', '/'))
        .toSet();
    media = MediaResolver.fromJson(assets, readData('pictures.json'));
  });

  test('every thing uses only dictionary fields and values', () {
    for (final e in entities) {
      for (final field in e.fields.keys) {
        final d = registry.byId(field);
        expect(d, isNotNull, reason: '${e.id}: "$field" is not in the dictionary');
        final value = e.valueFor(field)!;
        expect(value == 'depends' || d!.values.containsKey(value), isTrue,
            reason: '${e.id}: "$field: $value" is not an allowed value');
      }
    }
  });

  test('tiles and voice use the name the child says; the data keeps the full name', () {
    expect(thing('tyrannosaurus_rex').name, 'Tyrannosaurus rex');
    expect(thing('tyrannosaurus_rex').label, 'T. rex');
    expect(thing('pterodactylus').label, 'Pterodactyl');
    expect(thing('cow').label, 'Cow');
  });

  for (final seed in [1, 2, 3, 4, 5]) {
    test('the game starts at the seed, one named question per board (seed $seed)',
        () async {
      final g = await start(seed);

      for (int n = 0; n < 3; n++) {
        final b = g.board!;
        expect(b.dimension.id, settings.startField);
        expect(g.prompt, 'What kind of thing is it?');
        expect(g.pathLabels, [settings.startLabel]);
        expect(b.groups.map((grp) => grp.value).toSet(),
            {'animal', 'plant', 'nature_not_alive', 'made_by_people'});

        // No picture/text style mix that could give a group away.
        expect(b.tiles.where((e) => !media.hasPicture(e)).map((e) => e.name), isEmpty,
            reason: 'every tile on the seed board should have a picture');

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
    final g = await start(11);
    final groups = g.board!.groups;

    expect(play(g, groups[0].items), SubmitResult.correct);

    // 3 from one group + 1 from another = one away.
    final nearMiss = [...groups[1].items.take(3), groups[2].items.first];
    expect(play(g, nearMiss), SubmitResult.oneAway);
    expect(g.mistakes, 1);
    expect(g.selected, isEmpty);
  });

  test('Animals opens into kinds of animal, with dinosaurs kept in play', () async {
    final g = await start(3);
    final animals = g.board!.groups.singleWhere((x) => x.value == 'animal');

    // Can't dig deeper before the board is solved.
    expect(g.canDescend(animals), isFalse);
    solve(g);
    expect(g.canDescend(animals), isTrue);
    for (final other in g.board!.groups.where((x) => x.value != 'animal')) {
      expect(g.canDescend(other), isFalse,
          reason: '${other.label} has no deeper 4×4, so no "dig deeper"');
    }

    g.descendInto(animals);
    expect(g.pathLabels, [settings.startLabel, 'Animals']);
    expect(g.board!.dimension.id, 'kind_of_animal');
    final kinds = g.board!.groups.map((x) => x.value).toSet();
    expect(kinds, contains('dinosaur'));
    expect(kinds, isNot(contains('amphibian')),
        reason: 'a kind with fewer than four familiar things stays off the board');

    g.back();
    expect(g.atRoot, isTrue);
  });

  test('a group opens only where a full board exists inside it', () async {
    final repo = repoWithSeed(7);
    final g = await start(7, repo: repo);
    solve(g);
    g.descendInto(g.board!.groups.singleWhere((x) => x.value == 'animal'));
    solve(g);

    final kindsOfDinosaur = registry.byId('kind_of_dinosaur')!;
    final fullKinds = kindsOfDinosaur.values.keys
        .where((v) => entities.where((e) => e.isIn('kind_of_dinosaur', v)).length >= 4)
        .length;
    final dinosaurs = g.board!.groups.singleWhere((x) => x.value == 'dinosaur');
    expect(g.canDescend(dinosaurs), fullKinds >= 4,
        reason: 'Dinosaurs opens once every kind of dinosaur has four names');
    for (final grp in g.board!.groups) {
      final filter = <PathFilter>[('kind_of_thing', 'animal'), (grp.dimId, grp.value)];
      expect(g.canDescend(grp), repo.assembler.boardableDimensions(filter).isNotEmpty);
    }
  });

  test('an academic field is stored but never sorts a board', () {
    expect(registry.byId('dinosaur_academic')!.sortsBoards, isFalse);
    expect(thing('pteranodon').valueFor('dinosaur_academic'), 'false');
    expect(thing('triceratops').valueFor('dinosaur_academic'), 'true');
    expect(thing('cow').valueFor('dinosaur_academic'), isNull);

    final asm = repoWithSeed(1).assembler;
    for (final filter in <List<PathFilter>>[
      const [],
      const [('kind_of_thing', 'animal')],
      const [('kind_of_thing', 'animal'), ('kind_of_animal', 'dinosaur')],
    ]) {
      expect(asm.boardableDimensions(filter).map((d) => d.id),
          isNot(contains('dinosaur_academic')));
    }
  });

  test('boards draw on all the familiar things, not the same few', () {
    final seen = <String>{};
    for (int seed = 0; seed < 40; seed++) {
      final board = repoWithSeed(seed).assembler.assemble(
          filter: const [('kind_of_thing', 'animal')],
          dimension: registry.byId('kind_of_animal')!,
          preferValues: settings.keepInPlay['kind_of_animal']!);
      seen.addAll(board!.groups
          .singleWhere((x) => x.value == 'dinosaur')
          .items
          .map((e) => e.id));
    }
    expect(seen.length, greaterThan(8),
        reason: 'his dinosaurs are all familiar, so many of them should turn up');
  });
}
