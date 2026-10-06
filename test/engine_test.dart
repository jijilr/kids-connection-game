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

  test('the animals on the seed board come from four different kinds', () async {
    for (int seed = 0; seed < 30; seed++) {
      final g = await start(seed);
      final animals = g.board!.groups.singleWhere((x) => x.value == 'animal').items;
      final kinds = animals.map((e) => e.valueFor('kind_of_animal')).toList();
      expect(kinds.toSet().length, 4, reason: 'seed $seed gave $kinds');
      expect(kinds.where((k) => k == 'dinosaur').length, lessThanOrEqualTo(1));
    }
  });

  test('no group is filled by one sub-kind', () {
    for (int seed = 0; seed < 30; seed++) {
      final board = repoWithSeed(seed).assembler.assemble(
          filter: const [('kind_of_thing', 'animal')],
          dimension: registry.byId('kind_of_animal')!,
          preferValues: settings.keepInPlay['kind_of_animal']!);
      final dinosaurs = board!.groups.singleWhere((x) => x.value == 'dinosaur').items;
      final kinds = dinosaurs.map((e) => e.valueFor('kind_of_dinosaur')).toSet();
      expect(kinds.length, greaterThan(1), reason: 'seed $seed gave $kinds');
    }
  });

  test('every tile on a board is drawn in the same style', () async {
    String look(EntityMedia m) =>
        m.image != null ? 'photo' : (m.emoji != null ? 'emoji' : 'name only');
    for (int seed = 0; seed < 30; seed++) {
      final g = await start(seed);
      expect(g.openTiles.map((e) => look(g.tileMedia(e))).toSet(), hasLength(1),
          reason: 'seed board, seed $seed');
      solve(g);
      g.descendInto(g.board!.groups.singleWhere((x) => x.value == 'animal'));
      expect(g.openTiles.map((e) => look(g.tileMedia(e))).toSet(), hasLength(1),
          reason: 'animals board, seed $seed');
    }
  });

  test('a held-back kind stays off every board', () async {
    expect(settings.holdBack['kind_of_animal'], contains('amphibian'));
    for (int seed = 0; seed < 30; seed++) {
      final g = await start(seed);
      expect(g.board!.tiles.where((e) => e.isIn('kind_of_animal', 'amphibian')), isEmpty);
      solve(g);
      g.descendInto(g.board!.groups.singleWhere((x) => x.value == 'animal'));
      expect(g.board!.tiles.where((e) => e.isIn('kind_of_animal', 'amphibian')), isEmpty);
    }
  });

  group('one clean solution', () {
    // 16 or 32 made-up things carrying two four-valued fields, "shape" and "colour".
    final dictionary = DimensionRegistry({
      'shape': const Dimension(
          id: 'shape',
          question: 'What shape is it?',
          values: {'a': 'A', 'b': 'B', 'c': 'C', 'd': 'D'}),
      'colour': const Dimension(
          id: 'colour',
          question: 'What colour is it?',
          values: {'w': 'W', 'x': 'X', 'y': 'Y', 'z': 'Z'}),
    });
    Entity made(String shape, String colour, int n) => Entity(
        id: '$shape$colour$n', name: '$shape$colour$n', fields: {'shape': shape, 'colour': colour});

    test('a board that also sorts cleanly by another field is refused', () {
      // One thing per shape-and-colour pair: any board by shape is also a board by colour.
      final grid = [
        for (final s in ['a', 'b', 'c', 'd'])
          for (final c in ['w', 'x', 'y', 'z']) made(s, c, 0),
      ];
      final asm = BoardAssembler(grid, dictionary, random: Random(1));
      expect(asm.secondSolution(grid, dictionary.byId('shape')!)!.id, 'colour');
      expect(asm.assemble(dimension: dictionary.byId('shape')!), isNull);
    });

    test('it rebuilds until the board has only one clean solution', () {
      // Two things per pair: some boards by shape also sort by colour, most do not.
      final things = [
        for (final s in ['a', 'b', 'c', 'd'])
          for (final c in ['w', 'x', 'y', 'z'])
            for (final n in [0, 1]) made(s, c, n),
      ];
      for (int seed = 0; seed < 50; seed++) {
        final asm = BoardAssembler(things, dictionary, random: Random(seed));
        final board = asm.assemble(dimension: dictionary.byId('shape')!);
        expect(board, isNotNull);
        expect(asm.secondSolution(board!.tiles, board.dimension), isNull, reason: 'seed $seed');
      }
    });

    test('no board built from the real data has a second clean solution', () async {
      for (int seed = 0; seed < 30; seed++) {
        final repo = repoWithSeed(seed);
        final g = await start(seed, repo: repo);
        expect(repo.assembler.secondSolution(g.board!.tiles, g.board!.dimension), isNull);
        solve(g);
        g.descendInto(g.board!.groups.singleWhere((x) => x.value == 'animal'));
        expect(repo.assembler.secondSolution(g.board!.tiles, g.board!.dimension), isNull);
      }
    });
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
