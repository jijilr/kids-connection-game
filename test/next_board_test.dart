import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:connections_game/models/dimension.dart';
import 'package:connections_game/models/game_settings.dart';
import 'package:connections_game/providers/engine_provider.dart';
import 'package:connections_game/services/board_assembler.dart';
import 'package:connections_game/services/content_repository.dart';
import 'package:connections_game/services/media.dart';
import 'package:connections_game/services/progress.dart';

/// What happens after a board is solved (the owner's ruling of 7 Oct 2026): "Dig deeper"
/// where there is a board inside, leaning toward the branch he has visited least; where
/// there is none, a parallel board at the same depth at once, and an order for more.
/// And the one way a board is made: makeBoard.
Map<String, dynamic> readData(String file) =>
    jsonDecode(File('Assets/data/$file').readAsStringSync()) as Map<String, dynamic>;

late DimensionRegistry registry;

ContentRepository repo(int seed) {
  final assets = Directory('Assets')
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path.replaceAll('\\', '/'))
      .toSet();
  registry = DimensionRegistry.fromJson(readData('dictionary.json'));
  return ContentRepository.fromData(
      ContentRepository.thingsFromJson(readData('things.json')),
      registry,
      GameSettings.fromJson(readData('settings.json')),
      random: Random(seed),
      media: MediaResolver.fromJson(assets, readData('pictures.json')));
}

void solve(EngineProvider g) {
  for (final grp in [...g.board!.groups]) {
    for (final e in grp.items) {
      g.toggle(e);
    }
    g.submit();
  }
}

/// Play down to a circle by the values that lead to it, taking fresh boards until the
/// wanted group is on the board.
void goTo(EngineProvider g, List<String> values) {
  for (final value in values) {
    for (int tries = 0; tries < 40 && !g.board!.groups.any((x) => x.value == value); tries++) {
      g.newBoard();
    }
    solve(g);
    g.descendInto(g.board!.groups.singleWhere((x) => x.value == value));
  }
}

void main() {
  var now = DateTime.utc(2026, 10, 7, 12);
  DateTime clock() => now = now.add(const Duration(seconds: 1));

  test('makeBoard gives sixteen things in four groups with one clean solution, or nothing', () {
    final r = repo(1);
    final start = registry.byId(readData('settings.json')['start']['field'] as String)!;
    for (int depth = 0; depth <= 2; depth++) {
      for (final circle in r.assembler.circlesAtDepth(depth, start)) {
        final board = r.assembler.makeBoard(BoardContext(
            filter: circle, dimension: circle.isEmpty ? start : null))!;
        expect(board.tiles, hasLength(16), reason: '$circle');
        expect(board.groups, hasLength(4));
        expect(board.groups.every((g) => g.items.length == 4), isTrue);
        expect(r.assembler.secondSolution(board.tiles, board.dimension), isNull, reason: '$circle');
        expect(board.style, isNotNull, reason: 'drawn in pictures, never names only');
      }
    }
    // a circle with no field of its own makes no board: it is never padded or sorted by something shallower
    const noField = <PathFilter>[('kind_of_thing', 'animal'), ('kind_of_animal', 'amphibian')];
    expect(r.assembler.makeBoard(const BoardContext(filter: noField)), isNull);
  });

  test('a fresh board in the same circle is not the same sixteen again', () async {
    final g = EngineProvider(repo: repo(2), random: Random(2), clock: clock);
    await g.init();
    for (int i = 0; i < 5; i++) {
      final before = {for (final e in g.board!.tiles) e.id};
      g.newBoard();
      expect({for (final e in g.board!.tiles) e.id}, isNot(equals(before)));
    }
  });

  test('Dig deeper leans toward the branch he has visited least', () async {
    final store = MemoryProgressStore();
    final visited = Progress();
    for (int i = 0; i < 6; i++) {
      visited.opened('animal', now);
      visited.opened('made_by_people', now);
    }
    visited.opened('plant', now);
    await store.save(visited);
    final g = EngineProvider(repo: repo(3), random: Random(3), progressStore: store, clock: clock);
    await g.init();
    solve(g);
    expect(g.diggable, isNotEmpty);
    final least = g.suggestedDig!;
    final visits = g.progress.timesOpened(least.value);
    expect(g.diggable.every((x) => g.progress.timesOpened(x.value) >= visits), isTrue);
    expect(least.value, 'nature_not_alive', reason: 'the one branch he has never opened');
    expect(g.atADeadEnd, isFalse);
  });

  test('with nowhere deeper to go he gets a parallel board at once, and an order is placed', () async {
    final store = MemoryProgressStore();
    final g = EngineProvider(repo: repo(4), random: Random(4), progressStore: store, clock: clock);
    await g.init();
    goTo(g, ['made_by_people', 'vehicle']);
    expect(g.pathLabels, hasLength(3));
    solve(g);
    expect(g.atADeadEnd, isTrue, reason: 'no group of Vehicles has a board inside it yet');
    expect(g.suggestedDig, isNull);
    expect(g.progress.orders.keys, contains('made_by_people/vehicle'));

    // the next board is another circle at the same depth, and never the one just left
    final seen = <String>['made_by_people/vehicle'];
    for (int i = 0; i < 4; i++) {
      g.nextBoard();
      final here = Progress.boardId(g.board!.filter);
      expect(g.board!.tiles, hasLength(16));
      expect(g.pathLabels, hasLength(3), reason: 'the same depth');
      expect(here, isNot(seen.last));
      seen.add(here);
    }
    // not recently seen: he is taken round the other circles before any comes again
    expect(seen.toSet().length, greaterThanOrEqualTo(min(5, seen.length)));
    // and the way back to the seed is intact
    g.back();
    g.back();
    expect(g.atRoot, isTrue);

    // the saved file carries the order for the job to read
    final file = jsonDecode(g.progress.toFileText()) as Map<String, dynamic>;
    expect((file['orders'] as Map).keys, contains('made_by_people/vehicle'));
    expect(Progress.fromJson(file).orders['made_by_people/vehicle']!.solved, 1);
  });

  test('at the seed, where there is no parallel circle, the next board is a fresh seed board', () async {
    final g = EngineProvider(repo: repo(5), random: Random(5), clock: clock);
    await g.init();
    final before = {for (final e in g.board!.tiles) e.id};
    g.nextBoard();
    expect(g.atRoot, isTrue);
    expect({for (final e in g.board!.tiles) e.id}, isNot(equals(before)));
  });
}
