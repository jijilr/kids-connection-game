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
        // One allowed value; or several, for a thing that fits more than one; or "depends".
        final raw = e.fields[field];
        final values = raw is List ? raw.map((v) => '$v').toList() : ['$raw'];
        expect(raw == 'depends' || values.every(d!.values.containsKey), isTrue,
            reason: '${e.id}: "$field: $raw" is not an allowed value');
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

  test('each seed group opens into a board of its own, or not at all', () async {
    final repo = repoWithSeed(5);
    final g = await start(5, repo: repo);
    solve(g);
    final seedGroups = [...g.board!.groups];
    for (final grp in seedGroups) {
      final filter = <PathFilter>[(grp.dimId, grp.value)];
      final inside = repo.assembler.boardableDimensions(filter);
      final opens =
          inside.isNotEmpty && repo.assembler.hasPictureBoard(filter, inside.first);
      expect(g.canDescend(grp), opens, reason: grp.label);
      if (!opens) continue;
      g.descendInto(grp);
      expect(g.board!.dimension.id, inside.first.id);
      expect(g.board!.groups, hasLength(4));
      expect(repo.assembler.secondSolution(g.board!.tiles, g.board!.dimension), isNull);
      g.back();
      solve(g); // back gives a fresh seed board; solve it so the next group can be opened
    }
    expect(repo.assembler.boardableDimensions(const [('kind_of_thing', 'made_by_people')]).first.id,
        'kind_of_made_thing');
    expect(repo.assembler.boardableDimensions(const [('kind_of_thing', 'plant')]).first.id,
        'kind_of_plant');
  });

  test('a thing that fits two groups stays off the board sorted by that field', () {
    final rain = thing('rain');
    expect(rain.fields['kind_of_nature'], ['sky', 'water']);
    expect(rain.isIn('kind_of_nature', 'sky'), isFalse);
    expect(rain.isIn('kind_of_nature', 'water'), isFalse);

    // A made-up board with one such thing among plenty of ordinary ones.
    final dictionary = DimensionRegistry({
      'k': const Dimension(
          id: 'k', question: 'Which?', values: {'a': 'A', 'b': 'B', 'c': 'C', 'd': 'D'}),
    });
    final things = [
      for (final v in ['a', 'b', 'c', 'd'])
        for (int n = 0; n < 4; n++) Entity(id: '$v$n', name: '$v$n', fields: {'k': v}),
      const Entity(id: 'both', name: 'both', familiar: 1.0, fields: {'k': ['a', 'b']}),
    ];
    for (int seed = 0; seed < 20; seed++) {
      final board = BoardAssembler(things, dictionary, random: Random(seed))
          .assemble(dimension: dictionary.byId('k')!);
      expect(board!.tiles.map((e) => e.id), isNot(contains('both')));
    }
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
      final inside = repo.assembler.boardableDimensions(filter);
      expect(g.canDescend(grp),
          inside.isNotEmpty && repo.assembler.hasPictureBoard(filter, inside.first));
    }
  });

  test('Vegetable plants, Vehicles, Things in the house and Mammals each open into a board of pictures', () {
    const circles = <(List<PathFilter>, String)>[
      ([('kind_of_thing', 'plant'), ('kind_of_plant', 'vegetable')], 'part_we_eat'),
      ([('kind_of_thing', 'made_by_people'), ('kind_of_made_thing', 'vehicle')], 'where_it_travels'),
      ([('kind_of_thing', 'made_by_people'), ('kind_of_made_thing', 'household')], 'kind_of_house_thing'),
      // the first field chosen from the field library by the rules, not approved by hand
      ([('kind_of_thing', 'animal'), ('kind_of_animal', 'mammal')], 'pet_farm_or_wild'),
    ];
    for (final (filter, field) in circles) {
      for (int seed = 0; seed < 20; seed++) {
        final repo = repoWithSeed(seed);
        final inside = repo.assembler.boardableDimensions(filter);
        expect(inside.map((d) => d.id), [field], reason: '$filter');
        expect(repo.assembler.hasPictureBoard(filter, inside.first), isTrue, reason: field);
        final board = repo.assembler.assemble(filter: filter, dimension: inside.first)!;
        expect(board.groups, hasLength(4));
        expect(board.style, isNotNull, reason: 'drawn, not names only');
        expect(board.tiles.every(media.hasPicture), isTrue);
        expect(repo.assembler.secondSolution(board.tiles, board.dimension), isNull, reason: field);
      }
    }
    // the scientist's answer for maize is kept, and sorts nothing
    expect(thing('maize_plant').valueFor('kind_of_plant'), 'vegetable');
    expect(thing('maize_plant').valueFor('kind_of_plant_academic'), 'grass_grain');
    expect(
        repoWithSeed(1)
            .assembler
            .boardableDimensions(const [('kind_of_thing', 'plant')]).map((d) => d.id),
        isNot(contains('kind_of_plant_academic')));
  });

  test('approved tiles ship with the game and are the first choice of style', () {
    final lotus = media.forEntity(thing('lotus'));
    expect(lotus.art, 'Assets/pictures/lotus.webp');
    expect(File(lotus.art!).existsSync(), isTrue);
    expect(entities.where((e) => media.forEntity(e).art == null), isEmpty,
        reason: 'every thing in the game has an approved drawn tile');
    expect(media.forEntity(Entity(id: 'not_drawn', name: 'Not drawn', fields: {})).art, isNull,
        reason: 'a thing with no approved tile has no drawn picture');
    expect(media.inStyle(thing('lotus'), 0).art, isNotNull);
    expect(media.inStyle(thing('lotus'), 2).art, isNull, reason: 'an emoji board shows emoji only');

    // A board whose 16 things all have drawn tiles is drawn in them.
    final dictionary = DimensionRegistry({
      'k': const Dimension(
          id: 'k', question: 'Which?', values: {'a': 'A', 'b': 'B', 'c': 'C', 'd': 'D'}),
    });
    final things = [
      for (final v in ['a', 'b', 'c', 'd'])
        for (int n = 0; n < 4; n++) Entity(id: '$v$n', name: '$v$n', fields: {'k': v}),
    ];
    final drawn = MediaResolver({for (final t in things) 'Assets/pictures/${t.id}.webp'});
    final board = BoardAssembler(things, dictionary, random: Random(1), styles: drawn.styles)
        .assemble(dimension: dictionary.byId('k')!)!;
    expect(board.style, 0);
    expect(board.tiles.every((t) => drawn.inStyle(t, board.style).art != null), isTrue);
  });

  test('a board that could only show names stays closed to the child', () async {
    expect(settings.boardsNeedPictures, isTrue);
    final repo = repoWithSeed(2);
    final g = await start(2, repo: repo);
    solve(g);
    for (final grp in g.board!.groups) {
      final filter = <PathFilter>[(grp.dimId, grp.value)];
      final inside = repo.assembler.boardableDimensions(filter);
      if (inside.isEmpty) continue;
      // The board exists in the data. Whether the child may open it depends on pictures.
      final board = repo.assembler.assemble(filter: filter, dimension: inside.first)!;
      expect(g.canDescend(grp), board.style != null, reason: grp.label);
    }
    // Things people make has pictures throughout, so it is open.
    expect(g.canDescend(g.board!.groups.singleWhere((x) => x.value == 'made_by_people')), isTrue);
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
    String look(EntityMedia m) => m.art != null
        ? 'drawn tile'
        : (m.image != null ? 'photo' : (m.emoji != null ? 'emoji' : 'name only'));
    for (int seed = 0; seed < 30; seed++) {
      final g = await start(seed);
      expect(g.openTiles.map((e) => look(g.tileMedia(e))).toSet(), hasLength(1),
          reason: 'seed board, seed $seed');
      solve(g);
      for (final value in ['animal', 'plant', 'made_by_people']) {
        final grp = g.board!.groups.singleWhere((x) => x.value == value);
        if (!g.canDescend(grp)) continue;
        g.descendInto(grp);
        expect(g.openTiles.map((e) => look(g.tileMedia(e))).toSet(), hasLength(1),
            reason: '$value board, seed $seed');
        g.back();
        solve(g);
      }
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
