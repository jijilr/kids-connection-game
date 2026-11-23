import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:connections_game/models/dimension.dart';
import 'package:connections_game/models/game_settings.dart';
import 'package:connections_game/models/group_words.dart';
import 'package:connections_game/providers/engine_provider.dart';
import 'package:connections_game/services/board_assembler.dart';
import 'package:connections_game/services/content_repository.dart';
import 'package:connections_game/services/media.dart';
import 'package:connections_game/services/progress.dart';

/// Where the button that ends a board leads (the owner's ruling of 23 Nov 2026): four
/// boards in five go deeper where he has shown mastery, one in five to a set where he
/// has not. Mastery of a group: found cleanly (no wrong guess took in its things, no clue
/// asked for it) on two different days.
Map<String, dynamic> readData(String file) =>
    jsonDecode(File('Assets/data/$file').readAsStringSync()) as Map<String, dynamic>;

ContentRepository repo(int seed) {
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
      words: GroupWordsBook.fromJson(readData('groups.json')));
}

/// A dice that always shows the same number, so a test can choose the four in five or
/// the one in five.
class Roll implements Random {
  Roll(this.value);
  double value;
  @override
  double nextDouble() => value;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

void solve(EngineProvider g) {
  for (final grp in [...g.board!.groups]) {
    if (g.solved.contains(grp)) continue;
    g.deselectAll();
    for (final e in grp.items) {
      g.toggle(e);
    }
    g.submit();
  }
}

void goTo(EngineProvider g, List<String> values) {
  for (final value in values) {
    for (int tries = 0; tries < 40 && !g.board!.groups.any((x) => x.value == value); tries++) {
      g.newBoard();
    }
    solve(g);
    g.descendInto(g.board!.groups.singleWhere((x) => x.value == value));
  }
}

final day1 = DateTime(2026, 11, 23, 10);
final day2 = DateTime(2026, 11, 24, 10);
final day3 = DateTime(2026, 11, 25, 10);

Future<MemoryProgressStore> storeWith(List<String> mastered) async {
  final store = MemoryProgressStore();
  final p = Progress();
  for (final id in mastered) {
    p
      ..found(id, day1, clean: true)
      ..found(id, day2, clean: true);
  }
  await store.save(p);
  return store;
}

void main() {
  test('a wrong guess or a clue makes a find not clean; the other groups stay clean', () async {
    final g = EngineProvider(repo: repo(3), random: Random(3), clock: () => day1);
    await g.init();
    final groups = {for (final x in g.board!.groups) x.value: x};

    // three plants and one thing from nature: one away, and both groups are shaken
    for (final e in [...groups['plant']!.items.take(3), groups['nature_not_alive']!.items.first]) {
      g.toggle(e);
    }
    expect(g.submit(), SubmitResult.oneAway);

    // a clue asked while two made things are chosen is a clue for Things people make
    g.toggle(groups['made_by_people']!.items[0]);
    g.toggle(groups['made_by_people']!.items[1]);
    expect(g.nextClue(), isNotNull);
    g.deselectAll();

    solve(g);
    expect(g.boardFinished, isTrue);
    expect(g.stars, 2, reason: 'the stars are as before: one mistake');
    final found = g.progress.groups;
    expect(found['animal']!.clean, 1, reason: 'no wrong guess took in an animal, and no clue was asked for them');
    expect(found['plant']!.clean, 0);
    expect(found['nature_not_alive']!.clean, 0);
    expect(found['made_by_people']!.clean, 0, reason: 'a clue was asked for it');
    for (final id in ['animal', 'plant', 'nature_not_alive', 'made_by_people']) {
      expect(found[id]!.found, 1, reason: 'every group is still counted as found');
    }
  });

  test('a group is mastered after clean finds on two different days, not two on one day', () async {
    final store = MemoryProgressStore();
    var today = day1;
    final g = EngineProvider(repo: repo(4), random: Random(4), progressStore: store, clock: () => today);
    await g.init();
    solve(g);
    g.newBoard();
    solve(g);
    expect(g.progress.groups['animal']!.clean, 2);
    expect(g.masteredGroup('animal'), isFalse, reason: 'two clean finds, but on one day');

    today = day2;
    final later = EngineProvider(repo: repo(5), random: Random(5), progressStore: store, clock: () => today);
    await later.init();
    solve(later);
    expect(later.masteredGroup('animal'), isTrue);
    expect(later.masteredGroup('animal/dinosaur'), isFalse, reason: 'never found: nothing is presumed');
  });

  test('four in five: deeper inside a group he has mastered', () async {
    final roll = Roll(0.1);
    final g = EngineProvider(
        repo: repo(6), random: roll, progressStore: await storeWith(['animal']), clock: () => day3);
    await g.init();
    solve(g);
    final next = g.nextStep!;
    expect(next.id, 'animal');
    expect(next.inside, isTrue);
    expect(next.mastered, isTrue);
    g.goNext();
    expect(g.pathLabels.last, 'Animals');
  });

  test('one in five: a set he has not mastered, the one he has visited least first', () async {
    final roll = Roll(0.9);
    final g = EngineProvider(
        repo: repo(7), random: roll, progressStore: await storeWith(['animal']), clock: () => day3);
    await g.init();
    solve(g);
    final next = g.nextStep!;
    expect(next.mastered, isFalse);
    expect(next.id, isNot('animal'));
    expect(next.inside, isTrue, reason: 'a group just found comes first');
  });

  test('mastery anywhere draws him there, even from another branch', () async {
    final roll = Roll(0.1);
    final g = EngineProvider(
        repo: repo(8), random: roll, progressStore: await storeWith(['animal/dinosaur']), clock: () => day3);
    await g.init();
    goTo(g, ['made_by_people', 'vehicle']);
    solve(g);
    expect(g.atADeadEnd, isTrue);
    final next = g.nextStep!;
    expect(next.id, 'animal/dinosaur', reason: 'he has shown he knows dinosaurs: go deeper there');
    expect(next.inside, isFalse);
    g.goNext();
    expect(g.pathLabels, ['Everything', 'Animals', 'Dinosaurs']);
    // the way back is intact
    g.back();
    expect(g.pathLabels.last, 'Animals');
  });

  test('with nothing mastered the four in five fall back to the least visited, so he is never stuck', () async {
    final g = EngineProvider(repo: repo(9), random: Roll(0.1), clock: () => day1);
    await g.init();
    solve(g);
    expect(g.nextStep!.mastered, isFalse);
    expect(g.nextStep!.inside, isTrue);
  });

  test('over many boards about four in five go where he has shown mastery', () async {
    final g = EngineProvider(
        repo: repo(10), random: Random(10), progressStore: await storeWith(['animal', 'plant']), clock: () => day3);
    await g.init();
    var deeper = 0;
    const boards = 60;
    for (int i = 0; i < boards; i++) {
      solve(g);
      if (g.nextStep!.mastered) deeper++;
      g.newBoard();
    }
    expect(deeper / boards, inInclusiveRange(0.65, 0.93), reason: '$deeper of $boards');
  });

  test('every board the button can lead to can be made', () async {
    final r = repo(11);
    final g = EngineProvider(repo: r, random: Random(11), progressStore: await storeWith(['animal']), clock: () => day3);
    await g.init();
    for (int i = 0; i < 5; i++) {
      solve(g);
      final next = g.nextStep;
      if (next != null) {
        expect(r.assembler.makeBoard(BoardContext(filter: next.filter)), isNotNull, reason: next.id);
      }
      g.goNext();
    }
  });
}
