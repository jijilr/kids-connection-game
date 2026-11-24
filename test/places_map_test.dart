import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:connections_game/models/dimension.dart';
import 'package:connections_game/models/game_settings.dart';
import 'package:connections_game/services/board_assembler.dart';
import 'package:connections_game/services/content_repository.dart';
import 'package:connections_game/services/media.dart';
import 'package:connections_game/services/progress.dart';

/// The map of every place (the owner, 24 Nov 2026: "some kind of json with meta data of
/// each node... that is the nerve system of the whole thing").
///
/// Step 1: the map is built by one program, tools/catalogue/places.py, into
/// Assets/data/places.json. Until the game reads it (step 2), the game still works the
/// places out for itself. This test holds the two together: on the real data, the map
/// and the game must say the same about every place.
Map<String, dynamic> readData(String file) =>
    jsonDecode(File('Assets/data/$file').readAsStringSync()) as Map<String, dynamic>;

void main() {
  late ContentRepository r;
  late Map<String, dynamic> places;
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
        media: MediaResolver.fromJson(assets, readData('pictures.json')));
    places = readData('places.json')['places'] as Map<String, dynamic>;
  });

  List<PathFilter> circlesOf(Map<String, dynamic> place) =>
      [for (final step in place['circles'] as List) ('${(step as List)[0]}', '${step[1]}')];

  List<Dimension> asked(List<PathFilter> filter) {
    final start = r.registry.byId(settings.startField)!;
    final own = r.assembler.questionsAt(filter);
    return filter.isEmpty ? [start, ...own.where((d) => d.id != start.id)] : own;
  }

  test('the places that can make a set are the same in the map and in the game', () {
    final game = {
      'seed',
      for (final f in r.assembler.circlesBelow(r.registry.byId(settings.startField)!)) Progress.boardId(f)
    };
    final map = {
      for (final e in places.entries)
        if ((e.value as Map)['state'] == 'ready') e.key
    };
    expect(map, game);
    expect(map, containsAll(['seed', 'animal', 'animal/wild_land', 'animal/mammal/wild_land']));
  });

  test('every place has the name the game gives it, and holds the same things', () {
    for (final entry in places.entries) {
      final place = entry.value as Map<String, dynamic>;
      final circles = circlesOf(place);
      expect(Progress.boardId(r.assembler.canon(circles)), entry.key, reason: 'named by its circles, in order');
      expect(circles, r.assembler.canon(circles), reason: '${entry.key}: its circles are kept in that order');
      final held = settings.holdBack;
      final inside = r.entities.where((e) =>
          !held.entries.any((h) => h.value.contains(e.valueFor(h.key))) &&
          circles.every((c) => e.isIn(c.$1, c.$2)));
      expect(place['things'], inside.length, reason: entry.key);
    }
  });

  test('every place asks the same questions, of the same kinds, in the map and in the game', () {
    for (final entry in places.entries) {
      final place = entry.value as Map<String, dynamic>;
      final circles = circlesOf(place);
      final asks = place['asks'] as List;
      expect([for (final a in asks) (a as Map)['question']], [for (final d in asked(circles)) d.id],
          reason: 'the questions asked at ${entry.key}');
      for (final a in asks.cast<Map<String, dynamic>>()) {
        final question = r.registry.byId(a['question'] as String)!;
        expect(a['makes_a_set'], r.assembler.hasPictureBoard(circles, question),
            reason: '${entry.key} by ${question.id}: whether it can make a set in pictures');
        final ready = r.assembler.kindsReady(circles, question).where((v) => v != Dimension.inBetween).toSet();
        final kinds = a['kinds'] as Map<String, dynamic>;
        expect({
          for (final k in kinds.entries)
            if ((k.value as Map)['ready'] == true) k.key
        }, ready, reason: '${entry.key} by ${question.id}: the kinds that can be shown');
        for (final k in kinds.entries) {
          expect((k.value as Map)['place'],
              Progress.boardId(r.assembler.canon([...circles, (question.id, k.key)])),
              reason: 'where the kind ${k.key} of ${entry.key} leads');
        }
      }
    }
  });

  test('a place where circles cross lies in each of them, and every wider place is on the map', () {
    final place = places['animal/mammal/wild_land'] as Map<String, dynamic>;
    expect((place['lies_in'] as Map).keys, unorderedEquals(['animal/mammal', 'animal/wild_land']));
    expect(place['reached_from'], unorderedEquals(['animal/mammal', 'animal/wild_land']),
        reason: 'a set in either of them leads here: two roads');
    expect((places['animal/wild_land'] as Map)['lies_in'], {
      'animal': ['pet_farm_or_wild', 'wild_land']
    });
    expect((places['animal'] as Map)['lies_in'], {
      'seed': ['kind_of_thing', 'animal']
    });
    for (final entry in places.entries) {
      final wider = (entry.value as Map)['lies_in'] as Map;
      if (entry.key != 'seed') expect(wider, isNotEmpty, reason: '${entry.key} hangs from somewhere');
      for (final other in wider.keys) {
        expect(places.containsKey(other), isTrue, reason: '${entry.key} lies in $other');
      }
    }
  });

  test('every place has a state, and a reason where it cannot be played', () {
    const states = {'ready', 'held', 'end', 'can be made', 'a group only'};
    for (final entry in places.entries) {
      final place = entry.value as Map<String, dynamic>;
      expect(states, contains(place['state']), reason: entry.key);
      if (place['state'] != 'ready') {
        expect((place['why'] as String).trim(), isNotEmpty, reason: '${entry.key} is ${place['state']}: why?');
      }
    }
  });
}
