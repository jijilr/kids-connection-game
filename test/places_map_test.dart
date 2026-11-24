import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:connections_game/models/dimension.dart';
import 'package:connections_game/models/game_settings.dart';
import 'package:connections_game/models/places_map.dart';
import 'package:connections_game/services/board_assembler.dart';
import 'package:connections_game/services/content_repository.dart';
import 'package:connections_game/services/media.dart';

import 'support/places_for.dart';

/// The map of every place (the owner, 24 Nov 2026: "some kind of json with meta data of
/// each node... that is the nerve system of the whole thing").
///
/// The map is built by one program, tools/catalogue/places.py, into
/// Assets/data/places.json, and since step 2 the game reads it and works out nothing
/// about places for itself. These tests hold the two ends together on the real data:
/// what the map promises, the game can do with the things it holds.
Map<String, dynamic> readData(String file) =>
    jsonDecode(File('Assets/data/$file').readAsStringSync()) as Map<String, dynamic>;

void main() {
  late ContentRepository r;
  late GameSettings settings;

  setUpAll(() {
    final assets = Directory('Assets')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll('\\', '/'))
        .toSet();
    settings = GameSettings.fromJson(readData('settings.json'));
    r = ContentRepository.fromData(
        ContentRepository.thingsFromJson(readData('things.json')),
        DimensionRegistry.fromJson(readData('dictionary.json')),
        settings,
        random: Random(1),
        media: MediaResolver.fromJson(assets, readData('pictures.json')),
        places: realPlaces());
  });

  test('where the map says a question makes a set, the game makes one, in pictures, of kinds the map calls ready', () {
    var sets = 0;
    for (final place in r.places.all) {
      for (final asked in place.asks.where((a) => a.makesASet)) {
        final question = r.registry.byId(asked.question)!;
        final board = r.assembler.makeBoard(BoardContext(filter: place.circles, dimension: question));
        expect(board, isNotNull, reason: '${place.id} by ${asked.question}: the map says a set can be made');
        expect(board!.style, isNotNull, reason: '${place.id}: in pictures');
        expect(board.tiles, hasLength(16));
        expect(r.assembler.secondSolution(board.tiles, question), isNull);
        final ready = {
          for (final k in asked.kinds.entries)
            if (k.value.ready) k.key,
          if (asked.inBetweenReady) Dimension.inBetween,
        };
        expect(ready, containsAll([for (final g in board.groups) g.value]),
            reason: '${place.id} by ${asked.question}: every group shown is a kind the map calls ready');
        sets++;
      }
    }
    expect(sets, greaterThanOrEqualTo(17), reason: 'sixteen places and more, one of them by two questions');
  });

  test('every place holds the things the map counts, under the name the map gives it', () {
    for (final place in r.places.all) {
      final held = settings.holdBack;
      final inside = r.entities.where((e) =>
          !held.entries.any((h) => h.value.contains(e.valueFor(h.key))) &&
          place.circles.every((c) => e.isIn(c.$1, c.$2)));
      final record = (readData('places.json')['places'] as Map)[place.id] as Map;
      expect(record['things'], inside.length, reason: place.id);
      expect(r.places.idOf(place.circles.reversed.toList()), place.id,
          reason: 'named by its circles, in whatever order they are given');
      for (final asked in place.asks) {
        for (final kind in asked.kinds.entries) {
          expect(kind.value.things,
              inside.where((e) => e.valueFor(asked.question) == kind.key).length,
              reason: '${place.id}: the things of the kind ${kind.key}');
          // a kind with things is a place on the map, found by its circles in any order
          if (kind.value.things > 0) {
            expect(r.places.idOf([(asked.question, kind.key), ...place.circles]), kind.value.place,
                reason: '${place.id}: where the kind ${kind.key} leads');
          }
        }
      }
    }
    expect(r.places.things, r.entities.length, reason: 'the map was built for these things');
  });

  test('a place where circles cross lies in each of them, and every wider place is on the map', () {
    final crossing = r.places['animal/mammal/wild_land']!;
    expect(crossing.liesIn.keys, unorderedEquals(['animal/mammal', 'animal/wild_land']));
    expect(crossing.reachedFrom, unorderedEquals(['animal/mammal', 'animal/wild_land']),
        reason: 'a set in either of them leads here: two roads');
    expect(r.places['animal/wild_land']!.liesIn, {'animal': ('pet_farm_or_wild', 'wild_land')});
    expect(r.places['animal']!.liesIn, {'seed': ('kind_of_thing', 'animal')});
    for (final place in r.places.all) {
      if (place.id != 'seed') expect(place.liesIn, isNotEmpty, reason: '${place.id} hangs from somewhere');
      for (final other in place.liesIn.keys) {
        expect(r.places[other], isNotNull, reason: '${place.id} lies in $other');
      }
      for (final road in place.reachedFrom) {
        expect(place.liesIn.containsKey(road), isTrue, reason: 'a road to ${place.id} comes from a wider place');
      }
    }
  });

  test('every place has a state, and a reason where it cannot be played', () {
    const states = {'ready', 'held', 'end', 'can be made', 'a group only'};
    for (final place in r.places.all) {
      expect(states, contains(place.state), reason: place.id);
      expect(place.ready, place.state == 'ready', reason: '${place.id}: ready means a set can be made');
      if (!place.ready) expect(place.why.trim(), isNotEmpty, reason: '${place.id} is ${place.state}: why?');
    }
    expect(r.places.ready.map((p) => p.id),
        containsAll(['animal', 'animal/wild_land', 'animal/mammal/wild_land', 'made_by_people/toy/music']));
  });

  test('without a map the first set can still be played, and nothing beyond it', () {
    final bare = ContentRepository.fromData(
        ContentRepository.thingsFromJson(readData('things.json')),
        DimensionRegistry.fromJson(readData('dictionary.json')),
        settings,
        random: Random(2));
    expect(bare.places.isEmpty, isTrue);
    expect(bare.places.idOf(const [('kind_of_thing', 'animal')]), 'animal');
    expect(bare.places.ready, isEmpty);
  });
}
