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

/// Which set comes next (the owner's design of 24 Nov 2026). After each set its groups
/// are ranked by how well he did them: fewest wrong guesses that took in its things,
/// then no clue, and a tie goes to the one he attempted earliest. The groups he did well
/// become lines to follow, best first, the newest set's first. Four times in five the
/// button follows the first line whose set is ready; once in five it leads to a set he
/// has not proven. A line whose set is not ready stays at the front: the helper on the
/// owner's PC prepares it while he plays others.
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

BoardGroup group(EngineProvider g, String value) => g.board!.groups.singleWhere((x) => x.value == value);

void find(EngineProvider g, String value) {
  g.deselectAll();
  for (final e in group(g, value).items) {
    g.toggle(e);
  }
  expect(g.submit(), anyOf(SubmitResult.correct, SubmitResult.roundDone));
}

/// Solve what is left of the set, the groups named in [first] first.
void solve(EngineProvider g, [List<String> first = const []]) {
  final values = [
    ...first,
    for (final x in g.board!.groups)
      if (!first.contains(x.value)) x.value
  ];
  for (final value in values) {
    if (!g.solved.any((x) => x.value == value)) find(g, value);
  }
}

final day = DateTime(2026, 11, 24, 10);

void main() {
  test('the groups of a set are ranked: wrong guesses, then a clue, then attempted earliest', () async {
    final g = EngineProvider(repo: repo(3), random: Random(3), clock: () => day);
    await g.init();
    // three plants and one thing from nature: one away; both groups have a wrong guess
    for (final e in [...group(g, 'plant').items.take(3), group(g, 'nature_not_alive').items.first]) {
      g.toggle(e);
    }
    expect(g.submit(), SubmitResult.oneAway);
    // a clue asked while two made things are chosen is a clue for Things people make
    g.toggle(group(g, 'made_by_people').items[0]);
    g.toggle(group(g, 'made_by_people').items[1]);
    expect(g.nextClue(), isNotNull);

    solve(g, ['nature_not_alive', 'made_by_people', 'animal', 'plant']);
    expect([for (final x in g.ranked) x.value], ['animal', 'made_by_people', 'nature_not_alive', 'plant'],
        reason: 'animals: nothing wrong, no clue. Made things: a clue. Nature and plants: a wrong guess each, '
            'taken in by the same guess, so the one found first comes first');
    expect(g.didWell(group(g, 'animal')), isTrue);
    expect(g.didWell(group(g, 'made_by_people')), isFalse);
    expect(g.progress.lines, ['animal'], reason: 'only what he did well is a line to follow');
    expect(g.progress.groups['animal']!.clean, 1);
    expect(g.progress.groups['plant']!.clean, 0);
    expect(g.progress.groups['plant']!.found, 1);
    expect(g.stars, 2, reason: 'the stars are as before: one mistake');
  });

  test('a tie goes to the group he attempted earliest', () async {
    final g = EngineProvider(repo: repo(4), random: Roll(0.1), clock: () => day);
    await g.init();
    solve(g, ['made_by_people', 'plant', 'animal', 'nature_not_alive']);
    expect(g.progress.lines, ['made_by_people', 'plant', 'animal', 'nature_not_alive']);
    final next = g.nextStep!;
    expect(next.id, 'made_by_people');
    expect(next.inside, isTrue);
    expect(next.proven, isTrue);
    g.goNext();
    expect(g.pathLabels.last, 'Things people make');
  });

  test('a best line whose set is not ready waits at the front while he plays the next ready one', () async {
    final g = EngineProvider(repo: repo(5), random: Roll(0.1), clock: () => day);
    await g.init();
    solve(g, ['animal', 'made_by_people', 'nature_not_alive', 'plant']);
    g.goNext();
    expect(g.pathLabels.last, 'Animals');
    // a set of animals holding a kind with no set of its own yet
    const notReady = ['fish', 'reptile', 'insect'];
    for (int tries = 0; tries < 60 && !g.board!.groups.any((x) => notReady.contains(x.value)); tries++) {
      g.newBoard();
    }
    final deep = g.board!.groups.firstWhere((x) => notReady.contains(x.value)).value;
    solve(g, [deep]);
    // Animals holds six kinds and a set shows four (the owner's ruling of the evening of
    // 24 Nov 2026): the set is not used up, and comes once more before any kind is gone into
    expect(g.progress.lines.first, 'animal', reason: 'two kinds of animal are still untested');
    expect(g.progress.lines[1], 'animal/$deep', reason: 'what he did best: the helper prepares it');
    expect(g.nextStep!.id, 'animal');
    final firstRound = {for (final x in g.board!.groups) x.value};
    g.goNext();
    expect(g.pathLabels.last, 'Animals');
    final secondRound = {for (final x in g.board!.groups) x.value};
    expect(secondRound.difference(firstRound), hasLength(2), reason: 'the two kinds left');
    final waits = secondRound.firstWhere(notReady.contains);
    solve(g, [waits]);
    expect(g.progress.lines.first, 'animal/$waits', reason: 'what he did best: the helper prepares it');
    expect(g.progress.lines, isNot(contains('animal')), reason: 'every kind is tested: the set is used up');
    expect(g.progress.lines, containsAllInOrder(['made_by_people', 'nature_not_alive', 'plant']));
    final next = g.nextStep!;
    expect(next.id, isNot('animal/$waits'));
    expect(next.proven, isTrue);
    expect(g.progress.lines.indexOf(next.id), greaterThan(0), reason: 'the first line that is ready');
    final r = repo(5);
    expect(r.assembler.makeBoard(BoardContext(filter: next.filter)), isNotNull);
  });

  test('one in five: a set he has not proven, the one he has opened least, nearest first', () async {
    final g = EngineProvider(repo: repo(6), random: Roll(0.9), clock: () => day);
    await g.init();
    // plants and nature are taken in by a wrong guess; animals and made things are done well
    for (final e in [...group(g, 'plant').items.take(2), ...group(g, 'nature_not_alive').items.take(2)]) {
      g.toggle(e);
    }
    expect(g.submit(), SubmitResult.wrong);
    solve(g, ['animal', 'made_by_people']);
    expect(g.progress.lines, ['animal', 'made_by_people']);
    final next = g.nextStep!;
    expect(next.proven, isFalse);
    expect(['plant', 'nature_not_alive'], contains(next.id));
  });

  test('when no line is ready he still gets a set, so he never waits', () async {
    final g = EngineProvider(repo: repo(7), random: Roll(0.1), clock: () => day);
    await g.init();
    for (final grp in g.board!.groups) {
      g.toggle(grp.items.first);
    }
    expect(g.submit(), SubmitResult.wrong);
    solve(g);
    expect(g.progress.lines, isEmpty);
    expect(g.nextStep, isNotNull);
    expect(g.nextStep!.proven, isFalse);
  });

  test('the lines are kept between visits', () async {
    final store = MemoryProgressStore();
    final g = EngineProvider(repo: repo(8), random: Roll(0.1), progressStore: store, clock: () => day);
    await g.init();
    solve(g, ['plant', 'animal']);
    final later = EngineProvider(repo: repo(9), random: Roll(0.1), progressStore: store, clock: () => day);
    await later.init();
    expect(later.progress.lines.take(2), ['plant', 'animal']);
  });

  test('over many sets about four in five follow a line he has shown', () async {
    final g = EngineProvider(repo: repo(10), random: Random(10), clock: () => day);
    await g.init();
    var followed = 0;
    const sets = 60;
    for (int i = 0; i < sets; i++) {
      solve(g);
      if (g.nextStep!.proven) followed++;
      g.newBoard();
    }
    expect(followed / sets, inInclusiveRange(0.65, 0.93), reason: '$followed of $sets');
  });

  test('every set the button can lead to can be made', () async {
    final r = repo(11);
    final g = EngineProvider(repo: r, random: Random(11), clock: () => day);
    await g.init();
    for (int i = 0; i < 6; i++) {
      solve(g);
      final next = g.nextStep;
      if (next != null) {
        expect(r.assembler.makeBoard(BoardContext(filter: next.filter)), isNotNull, reason: next.id);
      }
      g.goNext();
    }
  });
}
