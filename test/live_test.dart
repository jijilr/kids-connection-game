import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:connections_game/providers/engine_provider.dart';
import 'package:connections_game/services/content_repository.dart';
import 'package:connections_game/services/live_link.dart';
import 'package:connections_game/services/progress.dart';

/// One game, dynamic data (the owner's design of 24 Nov 2026): the game tells the helper
/// on the owner's PC which lines he is following, and takes up a set as soon as the
/// helper has made it, with no rebuild. Here a stand-in plays the helper.
String readText(String file) => File('Assets/data/$file').readAsStringSync();

Set<String> filesOnDisk() => Directory('Assets')
    .listSync(recursive: true)
    .whereType<File>()
    .map((f) => f.path.replaceAll('\\', '/'))
    .toSet();

/// The helper, as the game sees it. Before the set of birds "is made" its things lack
/// the field that sorts them, exactly as a set not yet in the data.
class FakeHelper implements LiveLink {
  bool birdsMade = false;
  bool there = true;
  List<String> dead = [];
  final sent = <Map<String, dynamic>>[];
  final files = filesOnDisk();

  @override
  Future<LiveState?> state() async =>
      there ? LiveState(version: birdsMade ? 'v2' : 'v1', files: files, dead: dead) : null;

  @override
  Future<List<String>> send(Progress progress) async {
    sent.add(jsonDecode(jsonEncode(progress.toJson())) as Map<String, dynamic>);
    return dead;
  }

  @override
  Future<String?> read(String asset) async {
    final text = readText(asset.split('/').last);
    if (!birdsMade && asset.endsWith('places.json')) {
      // the map as it stood before the set of birds was made: Birds asks nothing yet
      final map = jsonDecode(text) as Map<String, dynamic>;
      final birds = (map['places'] as Map)['animal/bird'] as Map;
      birds['asks'] = [];
      birds['state'] = 'can be made';
      return jsonEncode(map);
    }
    if (birdsMade || !asset.endsWith('things.json')) return text;
    final data = jsonDecode(text) as Map<String, dynamic>;
    for (final thing in (data['things'] as Map).values) {
      final fields = (thing as Map)['fields'] as Map;
      if (fields['kind_of_animal'] == 'bird') fields.remove('pet_farm_or_wild');
    }
    return jsonEncode(data);
  }
}

class Roll implements Random {
  @override
  double nextDouble() => 0.1; // the four in five: follow his best line
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

void solve(EngineProvider g, [List<String> first = const []]) {
  final values = [
    ...first,
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

void main() {
  final day = DateTime(2026, 11, 24, 10);

  test('a set he earned is taken up as soon as the helper has made it', () async {
    final helper = FakeHelper();
    final g = EngineProvider(repo: ContentRepository(), random: Roll(), clock: () => day, live: helper);
    TestWidgetsFlutterBinding.ensureInitialized();
    await g.init();
    await g.syncLive();
    expect(g.board!.tiles, hasLength(16), reason: 'the data came through the helper');

    solve(g, ['animal']);
    g.goNext();
    expect(g.pathLabels.last, 'Animals');
    for (int tries = 0; tries < 60 && !g.board!.groups.any((x) => x.value == 'bird'); tries++) {
      g.newBoard();
    }
    solve(g, ['bird']);
    await g.syncLive();
    // six kinds of animal, four on a set: the set of animals comes once more, then his best line
    expect(g.progress.lines.take(2), ['animal', 'animal/bird']);
    g.goNext();
    expect(g.pathLabels.last, 'Animals');
    for (int tries = 0; tries < 60 && !g.board!.groups.any((x) => x.value == 'bird'); tries++) {
      g.newBoard();
    }
    solve(g, ['bird']);
    await g.syncLive();
    expect(g.progress.lines.first, 'animal/bird');
    expect(g.progress.lines.indexOf('animal'), greaterThan(0),
        reason: 'every kind of animal is tested; it waits, after his new lines, for its second question');
    expect(helper.sent.last['lines'], g.progress.lines, reason: 'the helper is told the lines he follows');
    expect(g.nextStep!.id, isNot('animal/bird'), reason: 'the set of birds is not made yet: he plays another');

    // the helper finishes the set while he is still on this screen
    helper.birdsMade = true;
    await g.syncLive();
    expect(g.nextStep!.id, 'animal/bird');
    expect(g.nextStep!.proven, isTrue);
    g.goNext();
    expect(g.pathLabels, ['Everything', 'Animals', 'Birds']);
    expect(g.board!.tiles, hasLength(16));
  });

  test('a line the helper says can never be made is let go, unless the game can open it by itself', () async {
    final helper = FakeHelper();
    final g = EngineProvider(repo: ContentRepository(), random: Roll(), clock: () => day, live: helper);
    TestWidgetsFlutterBinding.ensureInitialized();
    await g.init();
    solve(g, ['plant', 'animal']);
    expect(g.progress.lines.first, 'plant');
    // a line whose set is not made, and that the helper says it cannot make
    g.progress.lines.insert(0, 'animal/fish');
    helper.dead = ['animal/fish', 'plant'];
    await g.syncLive();
    expect(g.progress.lines, isNot(contains('animal/fish')));
    // The helper knows only the old single road. A place the game can open from what it
    // holds is not lost because the helper has never heard of it (circles that cross).
    expect(g.progress.lines.first, 'plant');
    expect(g.nextStep!.id, 'plant');
  });

  test('with no helper there the game plays from what it ships with', () async {
    final helper = FakeHelper()..there = false;
    final g = EngineProvider(repo: ContentRepository(), random: Roll(), clock: () => day, live: helper);
    TestWidgetsFlutterBinding.ensureInitialized();
    await g.init();
    expect(g.board!.tiles, hasLength(16));
    solve(g);
    await g.syncLive();
    expect(g.nextStep, isNotNull);
  });
}
