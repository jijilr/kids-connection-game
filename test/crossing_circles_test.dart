import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:connections_game/models/dimension.dart';
import 'package:connections_game/models/entity.dart';
import 'package:connections_game/models/game_settings.dart';
import 'package:connections_game/models/places_map.dart';
import 'package:connections_game/providers/engine_provider.dart';
import 'package:connections_game/screens/web_screen.dart';
import 'package:connections_game/services/board_assembler.dart';
import 'package:connections_game/services/content_repository.dart';
import 'package:connections_game/services/media.dart';
import 'package:connections_game/services/progress.dart';
import 'support/places_for.dart';

/// Circles that cross (the owner, on the night of 24 Nov 2026): "inspite of being
/// accomodating, we still assume concentric circles paradigm. but knowledge is never
/// that... how do we accomadate other possible circles along with the main center and
/// concentric circle". And: "yes, build the small proof."
///
/// The data was never concentric: a thing is a list of answers to questions. The game
/// was, by three choices, and each is undone here:
///   1. a question lived inside one circle  -> it belongs to every thing it is true of;
///   2. a place asked one question          -> it may ask more than one;
///   3. a place was named by the road to it -> it is named by the circles it lies in.
///
/// A small made-up game: four kinds, and the things of kind "a" answer two questions,
/// "sort" and "home" (as animals answer "what kind of animal" and "pet, farm or wild").
///
/// [homeless] names a sort whose things do not answer "home" at all, as no dinosaur
/// answers "pet, farm or wild".
ContentRepository game({int seed = 1, Map<String, dynamic> more = const {}, String? homeless}) {
  final things = <String, Map<String, dynamic>>{
    for (int s = 0; s < 4; s++)
      for (int h = 0; h < 4; h++)
        for (int i = 0; i < 4; i++)
          'a_s${s}h${h}_$i': {
            'name': 'a $s $h $i',
            'fields': {'kind': 'a', 'sort': 's$s', if ('s$s' != homeless) 'home': 'h$h'}
          },
    for (final k in ['b', 'c', 'd'])
      for (int i = 0; i < 6; i++)
        '${k}_$i': {
          'name': '$k $i',
          'fields': {'kind': k}
        },
  };
  final dictionary = <String, dynamic>{
    'version': 1,
    'fields': {
      'kind': {
        'wording': 'What kind is it?',
        'values': {'a': 'A', 'b': 'B', 'c': 'C', 'd': 'D'},
      },
      'sort': {
        'wording': 'Which sort?',
        'values': {'s0': 'S0', 's1': 'S1', 's2': 'S2', 's3': 'S3'},
      },
      'home': {
        'wording': 'Where is its home?',
        'values': {'h0': 'H0', 'h1': 'H1', 'h2': 'H2', 'h3': 'H3'},
      },
      ...more,
    }
  };
  return ContentRepository.fromData(
      [for (final e in things.entries) Entity.fromJson(e.key, e.value)],
      DimensionRegistry.fromJson(dictionary),
      const GameSettings(startField: 'kind', startLabel: 'Everything'),
      random: Random(seed),
      places: placesFor(dictionary: dictionary, things: things, startField: 'kind'));
}

class Roll implements Random {
  @override
  double nextDouble() => 0.1; // the four in five: follow his best line
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

Future<EngineProvider> start(ContentRepository repo) async {
  final g = EngineProvider(repo: repo, random: Roll(), clock: () => DateTime(2026, 11, 24, 23));
  await g.init();
  return g;
}

void solve(EngineProvider g, [List<String> first = const []]) {
  final onIt = {for (final x in g.board!.groups) x.value};
  final values = [
    ...first.where(onIt.contains),
    for (final x in g.board!.groups)
      if (!first.contains(x.value)) x.value
  ];
  for (final value in values) {
    if (g.solved.any((x) => x.value == value)) continue;
    g.deselectAll();
    for (final e in g.board!.groups.singleWhere((x) => x.value == value).items) {
      g.toggle(e);
    }
    g.submit();
  }
}

String here(EngineProvider g) => Progress.boardId(g.board!.filter);

void main() {
  test('a place may ask more than one question: each one that every thing of it answers', () {
    final r = game();
    List<String> asked(List<PathFilter> filter) => [for (final a in r.places.at(filter)?.asks ?? const <Asked>[]) a.question];
    expect(asked(const []), ['kind'], reason: 'only "kind" is answered by every thing');
    expect(asked(const [('kind', 'a')]), ['sort', 'home'], reason: 'two questions about the whole of a');
    expect(asked(const [('kind', 'a'), ('sort', 's0')]), ['home']);
    expect(asked(const [('kind', 'a'), ('home', 'h0')]), ['sort']);
    expect(asked(const [('kind', 'b')]), isEmpty);
  });

  test('a question has a reach: it is asked at the smallest place that holds every thing it is true of', () {
    // the things of sort s3 do not answer "home" at all
    final r = game(homeless: 's3');
    List<String> asked(List<PathFilter> filter) => [for (final a in r.places.at(filter)?.asks ?? const <Asked>[]) a.question];
    expect(asked(const []), ['kind'], reason: 'every thing that answers "home" is an a: its home is lower down');
    expect(asked(const [('kind', 'a')]), ['sort', 'home'],
        reason: 'not every a answers "home", but no smaller place holds all that do: its home is here');
    expect(asked(const [('kind', 'a'), ('sort', 's0')]), ['home']);
    expect(asked(const [('kind', 'a'), ('sort', 's3')]), isEmpty, reason: 'nothing there answers it');
    // a set sorted by it shows only things it is true of
    for (int i = 0; i < 10; i++) {
      final board =
          r.assembler.makeBoard(BoardContext(filter: const [('kind', 'a')], dimension: r.registry.byId('home')))!;
      expect(board.tiles.every((e) => e.valueFor('sort') != 's3'), isTrue);
    }
    // and the circle h0 is still a place: it crosses the sorts that answer
    final h0 = const [('kind', 'a'), ('home', 'h0')];
    expect(asked(h0), isEmpty, reason: 'three sorts answer: too few kinds for a set of their own');
    final home = r.places['a']!.asks.singleWhere((a) => a.question == 'home');
    expect(home.kinds.values.where((k) => k.ready), hasLength(4));
  });

  test('a place is named by the circles it lies in, not by the road to it', () {
    final r = game();
    final one = r.places.canon(const [('kind', 'a'), ('sort', 's1'), ('home', 'h0')]);
    final other = r.places.canon(const [('kind', 'a'), ('home', 'h0'), ('sort', 's1')]);
    expect(one, other);
    expect(Progress.boardId(one), 'a/s1/h0');
    // the places of the game: each once, however many roads lead to it
    final places = [for (final place in r.places.ready) place.id];
    expect(places.toSet(), hasLength(places.length), reason: 'no place twice');
    expect(places, containsAll(['a', 'a/s0', 'a/s3', 'a/h0', 'a/h3']));
    expect(places, isNot(contains('a/s0/h0')), reason: 'four things: a group, but no set of its own');
    expect(places, hasLength(9));
  });

  test('the same sixteen are never sorted two ways: one clean solution still rules', () {
    final r = game();
    final a = const [('kind', 'a')];
    for (final question in ['sort', 'home']) {
      for (int i = 0; i < 10; i++) {
        final board = r.assembler.makeBoard(BoardContext(filter: a, dimension: r.registry.byId(question)))!;
        expect(r.assembler.secondSolution(board.tiles, board.dimension), isNull,
            reason: 'a set by "$question" that the other question could not also sort four by four');
      }
    }
  });

  test('the game comes to the second question of a place by itself, after what he has just earned', () async {
    final g = await start(game());
    final sets = <String>[];
    void play([List<String> first = const []]) {
      sets.add('${here(g)} by ${g.board!.dimension.id}');
      solve(g, first);
    }

    play(['a']);
    g.goNext();
    play(['s0']);
    expect(sets.last, 'a by sort', reason: 'the question the place has always had comes first');
    // "sort" has no kind left. The place has another question, so it is not used up; but
    // it does not come at once: it follows the groups he has just done well.
    expect(g.progress.lines.first, 'a/s0');
    expect(g.progress.lines.take(4).toSet(), {'a/s0', 'a/s1', 'a/s2', 'a/s3'});
    expect(g.progress.lines[4], 'a');
    for (int i = 0; i < 4; i++) {
      g.goNext();
      play();
    }
    expect(sets[2], 'a/s0 by home');
    expect(sets.sublist(2).toSet(), {'a/s0 by home', 'a/s1 by home', 'a/s2 by home', 'a/s3 by home'});
    g.goNext();
    play(['h0']);
    expect(sets.last, 'a by home', reason: 'the same place, seen another way');
    expect(g.prompt, 'Where is its home?');
    expect(g.progress.lines, isNot(contains('a')), reason: 'both its questions are covered now');
    expect(g.progress.groups['a/h0']!.found, 1);

    // across: into the circle h0, which crosses every sort
    g.goNext();
    expect(here(g), 'a/h0');
    expect(g.board!.dimension.id, 'sort');
    expect(g.pathLabels, ['Everything', 'A', 'H0']);
    final before = g.progress.groups['a/s0/h0']!.found;
    solve(g, ['s0']);
    expect(g.progress.groups['a/s0/h0']!.found, before + 1,
        reason: 'the things of s0 in h0 are one place, whichever road he took');
    expect(g.progress.groups.keys.where((id) => id.startsWith('a/h0/')), isEmpty,
        reason: 'no second name for the same place');
  });

  test('on the web such a place is one knot, tied to every circle it lies in', () async {
    final g = await start(game());
    solve(g, ['a']);
    g.goNext();
    solve(g, ['s0']); // a by sort
    g.goNext();
    solve(g); // a/s0 by home: finds a/s0/h0 ...
    var web = {for (final n in g.web) n.id: n};
    expect(web['a/s0/h0']!.parent, 'a/s0');
    expect(web['a/s0/h0']!.label, 'H0', reason: 'named by what it adds to the place it hangs from');
    expect(web['a/s0/h0']!.also, isEmpty, reason: 'he has not found the circle h0 yet');

    for (int i = 0; i < 4; i++) {
      g.goNext();
      solve(g, ['h0']);
    }
    expect(g.progress.groups['a/h0']?.found, 1, reason: 'he has now played a by home');
    web = {for (final n in g.web) n.id: n};
    expect(web['a/h0']!.parent, 'a');
    expect(web['a/h0']!.label, 'H0');
    expect(web['a/s0/h0']!.parent, 'a/s0');
    expect(web['a/s0/h0']!.also, ['a/h0'], reason: 'now it is tied to both circles it lies in');
    expect(g.web.where((n) => n.id == 'a/s0/h0'), hasLength(1));
    final m = measureWeb(g.web);
    expect(m.deepest, 3, reason: 'depth is the number of circles a place lies inside, whatever the road');
  });

  testWidgets('the web draws the place once and says what the dotted threads mean', (tester) async {
    tester.view.physicalSize = const Size(900, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final g = await start(game());
    solve(g, ['a']);
    for (int i = 0; i < 6; i++) {
      g.goNext();
      solve(g, ['h0', 's0']);
    }
    expect(g.web.any((n) => n.also.isNotEmpty), isTrue);
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<EngineProvider>.value(value: g, child: const WebScreen()),
    ));
    for (int i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('web-a/s0/h0')), findsOneWidget);
    expect(find.textContaining('it lies in that circle too'), findsOneWidget);
  });

  test('a question merged into another is the same question: the game does not see it twice', () {
    // "home2" asked the same of a part of the game before "home" was asked of the whole
    final r = game(more: const {
      'home2': {
        'wording': 'Where is its home?',
        'sorts_boards': false,
        'merged_into': 'home',
        'values': {'h0': 'H0', 'h1': 'H1', 'h2': 'H2', 'h3': 'H3'},
      }
    });
    expect(r.registry.byId('home2'), isNull);
    expect(r.registry.byId('home'), isNotNull);
  });

  // ------------------------------------------------------------------ the real game
  // The small proof the owner asked for: "Is it mostly a pet, a farm animal or a wild
  // animal?" was asked of mammals, and again, as a second field, of birds. Since the
  // night of 24 Nov 2026 it is one question, asked of every animal it is true of.
  group('in the real game', () {
    Map<String, dynamic> readData(String file) =>
        jsonDecode(File('Assets/data/$file').readAsStringSync()) as Map<String, dynamic>;
    ContentRepository real(int seed) {
      final assets = Directory('Assets')
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path.replaceAll('\\', '/'))
          .toSet();
      return ContentRepository.fromData(
          ContentRepository.thingsFromJson(readData('things.json')),
          DimensionRegistry.fromJson(readData('dictionary.json')),
          GameSettings.fromJson(readData('settings.json')),
          random: Random(seed),
          media: MediaResolver.fromJson(assets, readData('pictures.json')),
          places: realPlaces());
    }

    const animals = [('kind_of_thing', 'animal')];

    test('Animals asks two questions, and the second has its home there', () {
      final r = real(1);
      List<String> asked(List<PathFilter> filter) => [for (final a in r.places.at(filter)!.asks) a.question];
      expect(asked(animals), ['kind_of_animal', 'pet_farm_or_wild']);
      expect(asked(const []), ['kind_of_thing'],
          reason: 'every thing that answers it is an animal: it is not a question about Everything');
      expect(r.registry.byId('pet_farm_or_wild_of_bird'), isNull, reason: 'the second copy is gone from the game');
      expect(asked(const [...animals, ('kind_of_animal', 'bird')]), ['pet_farm_or_wild'],
          reason: 'Birds is sorted by the same question as Mammals now');
    });

    test('"Pets at home" holds a dog and a parrot, and no set by this question shows a dinosaur', () {
      final r = real(2);
      final question = r.registry.byId('pet_farm_or_wild')!;
      final pets = <String>{};
      for (int i = 0; i < 40; i++) {
        final board = r.assembler.makeBoard(BoardContext(filter: animals, dimension: question))!;
        expect(r.assembler.secondSolution(board.tiles, question), isNull);
        expect(board.tiles.where((e) => e.valueFor('kind_of_animal') == 'dinosaur'), isEmpty,
            reason: 'the question is not about them: a dinosaur is gone');
        pets.addAll([for (final e in board.groups.singleWhere((x) => x.value == 'pet').items) e.valueFor('kind_of_animal')!]);
      }
      expect(pets, containsAll(['mammal', 'bird']), reason: 'one circle across two kinds of animal');
    });

    test('every place has one name, and the old names have not changed', () {
      final r = real(3);
      final ids = [for (final place in r.places.ready) place.id];
      expect(ids.toSet(), hasLength(ids.length), reason: 'no two places share a name');
      expect(ids, containsAll(['animal', 'animal/mammal', 'animal/bird', 'animal/dinosaur', 'animal/mammal/wild_land',
        'made_by_people/toy/music', 'plant/vegetable']));
      // a place reached by the new road has the name the old road gave it
      expect(r.places.idOf(const [...animals, ('pet_farm_or_wild', 'wild_land'), ('kind_of_animal', 'mammal')]),
          'animal/mammal/wild_land');
      // and the circle that crosses the kinds is a place of its own, with a set by kind of animal
      final wild = r.places.canon(const [...animals, ('pet_farm_or_wild', 'wild_land')]);
      expect(Progress.boardId(wild), 'animal/wild_land');
      expect(ids, contains('animal/wild_land'));
      final board = r.assembler
          .makeBoard(BoardContext(filter: wild, dimension: r.registry.byId(r.places.at(wild)!.asks.first.question)))!;
      expect(board.dimension.id, 'kind_of_animal');
      expect(board.tiles.every((e) => e.valueFor('pet_farm_or_wild') == 'wild_land'), isTrue);
    });

    test('he comes to "pet, farm or wild?" at Animals by himself, and from there across the kinds', () async {
      final g = EngineProvider(repo: real(4), random: Roll(), clock: () => DateTime(2026, 11, 24, 23));
      await g.init();
      final seen = <String>[];
      for (int i = 0; i < 40 && !seen.contains('animal by pet_farm_or_wild'); i++) {
        seen.add('${here(g)} by ${g.board!.dimension.id}');
        solve(g, ['animal', 'wild_land']);
        g.goNext();
      }
      expect(seen, contains('animal by pet_farm_or_wild'));
      expect(seen.where((s) => s == 'animal by kind_of_animal').length, 2, reason: 'six kinds: two rounds first');
      expect(g.progress.groups['animal/wild_land']?.found, 1);
      // the circle he has just found crosses the kinds of animal: it is a line, and it opens
      expect(g.progress.lines, contains('animal/wild_land'));
      for (int i = 0; i < 12 && here(g) != 'animal/wild_land'; i++) {
        solve(g);
        g.goNext();
      }
      expect(here(g), 'animal/wild_land');
      expect(g.prompt, 'What kind of animal is it?');
      expect(g.pathLabels, ['Everything', 'Animals', 'Wild animals on land']);
    });
  });
}
