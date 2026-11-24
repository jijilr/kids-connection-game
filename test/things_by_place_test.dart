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
import 'package:connections_game/services/live_link.dart';
import 'package:connections_game/services/media.dart';
import 'package:connections_game/services/progress.dart';

import 'support/places_for.dart';

/// Things stored by place (the map of places, step 5). A phone cannot load every thing
/// there is, so each place that can make a set has a small file of its own, and the game
/// takes it up when it goes there. However large the game grows, what a device holds is
/// what it has visited.
Map<String, dynamic> readData(String file) =>
    jsonDecode(File('Assets/data/$file').readAsStringSync()) as Map<String, dynamic>;

Set<String> filesOnDisk() => Directory('Assets')
    .listSync(recursive: true)
    .whereType<File>()
    .map((f) => f.path.replaceAll('\\', '/'))
    .toSet();

class Roll implements Random {
  @override
  double nextDouble() => 0.1; // the four in five: follow his best line
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
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

/// A helper that serves the real files, and can hand out one place's file as it was at
/// another moment.
class Served implements LiveLink {
  String? stale;
  final asked = <String>[];
  final files = filesOnDisk();

  @override
  Future<LiveState?> state() async => LiveState(version: 'v1', files: files);

  @override
  Future<List<String>> send(Progress progress) async => const [];

  @override
  Future<String?> read(String asset) async {
    asked.add(asset);
    final text = File(asset).readAsStringSync();
    if (stale != null && asset.endsWith(stale!)) {
      return jsonEncode({...jsonDecode(text) as Map<String, dynamic>, 'stamp': 'another-moment'});
    }
    return text;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final day = DateTime(2026, 11, 24, 23);
  final all = (readData('things.json')['things'] as Map).length;

  test('the game starts with the things of the first place only, and takes up a place when it goes there', () async {
    final repo = ContentRepository();
    final g = EngineProvider(repo: repo, random: Roll(), clock: () => day);
    await g.init();
    expect(repo.byPlace, isTrue);
    expect(repo.placesLoaded, 1);
    expect(repo.entities.length, lessThan(all ~/ 3), reason: 'not every thing there is: $all');
    expect(g.board!.tiles, hasLength(16));

    solve(g, ['animal']);
    expect(g.nextStep!.id, 'animal');
    await g.goNext();
    expect(g.pathLabels.last, 'Animals');
    expect(repo.placesLoaded, 2, reason: 'the things of Animals were taken up as he went there');
    expect(g.board!.tiles, hasLength(16));
    expect(g.board!.tiles.every((e) => e.valueFor('kind_of_thing') == 'animal'), isTrue);
    final held = repo.entities.length;
    expect(held, lessThan(all));

    // deeper, and across: each place brings only its own
    for (int i = 0; i < 6; i++) {
      solve(g);
      await g.goNext();
      expect(g.board, isNotNull);
      expect(g.board!.tiles, hasLength(16), reason: g.pathLabels.join(' > '));
    }
    expect(repo.placesLoaded, greaterThan(2));
    expect(repo.entities.length, greaterThan(held));
  });

  test('the place he will go to next is fetched while he looks at the set he has finished', () async {
    final helper = Served();
    final repo = ContentRepository();
    final g = EngineProvider(repo: repo, random: Roll(), clock: () => day, live: helper);
    await g.init();
    await g.syncLive();
    solve(g, ['animal']);
    await g.syncLive();
    await Future<void>.delayed(Duration.zero);
    expect(helper.asked, contains('Assets/data/places/animal.json'), reason: 'fetched ahead, before he asks');
    expect(repo.has('animal'), isTrue);
    await g.goNext();
    expect(g.pathLabels.last, 'Animals');
    expect(g.isLoading, isFalse);
  });

  test('a file written at another moment than the map is not used, and he stays where he is', () async {
    final helper = Served()..stale = 'places/animal.json';
    final repo = ContentRepository();
    final g = EngineProvider(repo: repo, random: Roll(), clock: () => day, live: helper);
    await g.init();
    await g.syncLive();
    solve(g, ['animal']);
    expect(await repo.ensure('animal'), isFalse);
    await g.goNext();
    expect(g.pathLabels, ['Everything'], reason: 'the things of Animals could not be had');
    expect(g.isLoading, isFalse);
    // once the file is whole again he can go
    helper.stale = null;
    await g.goNext();
    expect(g.pathLabels.last, 'Animals');
  });

  test('the file of each place is enough, by itself, for every set the map says can be made there', () {
    final map = realPlaces();
    final registry = DimensionRegistry.fromJson(readData('dictionary.json'));
    final settings = GameSettings.fromJson(readData('settings.json'));
    final media = MediaResolver.fromJson(filesOnDisk(), readData('pictures.json'));
    var files = 0;
    for (final place in map.all.where((p) => p.thingsFile != null)) {
      final file = readData(place.thingsFile!);
      expect(file['stamp'], map.stamp, reason: '${place.id}: written with the map');
      final things = [
        for (final e in (file['things'] as Map<String, dynamic>).entries)
          Entity.fromJson(e.key, e.value as Map<String, dynamic>)
      ];
      final alone = ContentRepository.fromData(things, registry, settings,
          random: Random(3), media: media, places: map);
      for (final asked in place.asks.where((a) => a.makesASet)) {
        for (int i = 0; i < 5; i++) {
          final board =
              alone.assembler.makeBoard(BoardContext(filter: place.circles, dimension: registry.byId(asked.question)));
          expect(board, isNotNull, reason: '${place.id} by ${asked.question}, from its own file');
          expect(board!.style, isNotNull, reason: '${place.id}: in pictures');
        }
        for (final kind in asked.kinds.entries.where((k) => k.value.ready)) {
          final here = things.where((e) => e.valueFor(asked.question) == kind.key).length;
          // twelve of a kind for each question asked there: a thing chosen for one question may
          // also be of a kind of the other
          expect(here, inInclusiveRange(4, 12 * place.asks.length),
              reason: '${place.id}: ${kind.key} has enough, and the file stays small');
        }
      }
      files++;
    }
    expect(files, map.ready.length + 1, reason: 'one file for each place that can make a set, the first included');
  });
}
