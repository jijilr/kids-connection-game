import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:connections_game/models/dimension.dart';
import 'package:connections_game/models/entity.dart';
import 'package:connections_game/models/game_settings.dart';
import 'package:connections_game/providers/engine_provider.dart';
import 'package:connections_game/screens/web_screen.dart';
import 'package:connections_game/services/board_assembler.dart';
import 'package:connections_game/services/content_repository.dart';
import 'package:connections_game/services/progress.dart';

/// The owner's rulings of the evening of 24 Nov 2026, each on a small made-up game so
/// that nothing here depends on what the real game holds today.
///
///  - A place may hold more kinds than the four a set shows. They are covered in the
///    fewest sets: five kinds in two (four, then the one left with three used again), six
///    in two (four, then the two left with two used again). The kinds used again are the
///    ones he did worst, shown with other things where they have them.
///  - One clean solution outranks the fewest sets: when a four cannot make such a set,
///    another used-again kind is tried, and only then does it cost him one more set.
///  - "Things resist binary classification": a thing with no single answer is not left
///    out and not forced into one answer. Four of them are the group "In between", which
///    waits until he knows the kinds on both sides.
///  - A branch can end: nothing lies below, and the game does not try to go there.
const letters = 'abcdefgh';

/// A game whose first question, "kind", has the kinds [kinds], each with [each] things.
/// [extra] adds whole things; [fields] adds fields to the dictionary.
ContentRepository game(List<String> kinds,
    {int each = 6,
    int seed = 1,
    Map<String, Map<String, dynamic>> extra = const {},
    Map<String, dynamic> fields = const {},
    Map<String, dynamic> kind = const {},
    Map<String, dynamic> ends = const {}}) {
  final things = <String, Map<String, dynamic>>{
    for (final k in kinds)
      for (int i = 0; i < each; i++)
        '${k}_${letters[i]}': {
          'name': '$k ${letters[i]}',
          'fields': {'kind': k}
        },
    ...extra,
  };
  final registry = DimensionRegistry.fromJson({
    'version': 1,
    'ends': ends,
    'fields': {
      'kind': {
        'wording': 'What kind is it?',
        'values': {for (final k in kinds) k: 'Kind $k'},
        ...kind,
      },
      ...fields,
    }
  });
  return ContentRepository.fromData(
      [for (final e in things.entries) Entity.fromJson(e.key, e.value)],
      registry,
      const GameSettings(startField: 'kind', startLabel: 'Everything'),
      random: Random(seed));
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
  final g = EngineProvider(repo: repo, random: Roll(), clock: () => DateTime(2026, 11, 24, 20));
  await g.init();
  return g;
}

Set<String> shown(EngineProvider g) => {for (final x in g.board!.groups) x.value};

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

/// A wrong guess that takes in two things of each of the kinds [a] and [b].
void guessWrong(EngineProvider g, String a, String b) {
  g.deselectAll();
  for (final kind in [a, b]) {
    for (final e in g.board!.groups.singleWhere((x) => x.value == kind).items.take(2)) {
      g.toggle(e);
    }
  }
  expect(g.submit(), isNot(SubmitResult.correct));
}

/// How many sets it takes until every kind has been shown, and what each set showed.
Future<List<Set<String>>> rounds(ContentRepository repo) async {
  final g = await start(repo);
  final sets = <Set<String>>[];
  for (int i = 0; i < 6; i++) {
    sets.add(shown(g));
    solve(g);
    if (!g.progress.lines.contains('seed')) break;
    expect(g.nextStep!.id, 'seed', reason: 'the set is not used up: it comes again at once');
    g.goNext();
  }
  return sets;
}

void main() {
  test('five kinds take two sets: four, then the one left with three used again', () async {
    final sets = await rounds(game(['a', 'b', 'c', 'd', 'e']));
    expect(sets, hasLength(2));
    final left = {'a', 'b', 'c', 'd', 'e'}.difference(sets[0]);
    expect(left, hasLength(1));
    expect(sets[1], containsAll(left));
    expect(sets[1].intersection(sets[0]), hasLength(3));
  });

  test('six kinds take two sets, not three: the two left come together', () async {
    final sets = await rounds(game(['a', 'b', 'c', 'd', 'e', 'f']));
    expect(sets, hasLength(2));
    expect(sets[1], containsAll({'a', 'b', 'c', 'd', 'e', 'f'}.difference(sets[0])));
    expect(sets[1].intersection(sets[0]), hasLength(2));
  });

  test('seven and eight kinds take two sets, nine take three, four take one', () async {
    for (final (count, wanted) in [(4, 1), (7, 2), (8, 2), (9, 3)]) {
      final kinds = [for (int i = 0; i < count; i++) 'k$i'];
      final sets = await rounds(game(kinds));
      expect(sets, hasLength(wanted), reason: '$count kinds');
      expect(sets.expand((s) => s).toSet(), kinds.toSet(), reason: 'every kind was shown');
    }
  });

  test('a set with more kinds to come is not used up, and the next one is', () async {
    final g = await start(game(['a', 'b', 'c', 'd', 'e']));
    solve(g);
    expect(g.progress.lines.first, 'seed');
    expect(g.nextStep!.label, 'Everything');
    expect(g.nextStep!.proven, isTrue);
    g.goNext();
    expect(g.pathLabels, ['Everything']);
    solve(g);
    expect(g.progress.lines, isNot(contains('seed')), reason: 'every kind has been tested');
  });

  test('the kinds used again are the ones he did worst', () async {
    for (int seed = 1; seed <= 6; seed++) {
      final g = await start(game(['a', 'b', 'c', 'd', 'e', 'f'], seed: seed));
      final first = shown(g).toList()..sort();
      final worst = {first[1], first[3]};
      guessWrong(g, first[1], first[3]);
      solve(g);
      expect(g.didWell(g.board!.groups.firstWhere((x) => x.value == first[1])), isFalse);
      g.goNext();
      final again = shown(g).intersection(first.toSet());
      expect(again, worst, reason: 'seed $seed: the two he got wrong, not the two he did well');
    }
  });

  test('a kind used again is shown with other things where it has them', () async {
    // eight things of each kind: the second time, four others
    var g = await start(game(['a', 'b', 'c', 'd', 'e'], each: 8));
    var before = {for (final x in g.board!.groups) x.value: {for (final e in x.items) e.id}};
    solve(g);
    g.goNext();
    for (final x in g.board!.groups.where((x) => before.containsKey(x.value))) {
      expect({for (final e in x.items) e.id}.intersection(before[x.value]!), isEmpty, reason: x.value);
    }
    // six of each: the two it has not shown, and two of the old
    g = await start(game(['a', 'b', 'c', 'd', 'e'], each: 6));
    before = {for (final x in g.board!.groups) x.value: {for (final e in x.items) e.id}};
    solve(g);
    g.goNext();
    for (final x in g.board!.groups.where((x) => before.containsKey(x.value))) {
      expect({for (final e in x.items) e.id}.difference(before[x.value]!), hasLength(2), reason: x.value);
    }
    // and what each kind was last shown with is kept between visits
    final saved = Progress.fromJson(g.progress.toJson());
    expect(saved.groups['a']!.things, hasLength(4));
  });

  group('one clean solution outranks the fewest sets', () {
    // Another field, "mark", sorts the things of a, b, c and e exactly as "kind" does: a
    // set of those four would have two right answers. d carries no mark.
    Map<String, Map<String, dynamic>> marked(List<String> kinds) => {
          for (final k in kinds)
            for (int i = 0; i < 6; i++)
              '${k}_${letters[i]}': {
                'name': '$k ${letters[i]}',
                'fields': {'kind': k, 'mark': 'm$k'}
              },
        };
    const mark = {
      'mark': {
        'wording': 'Which mark?',
        'sorts_boards': false,
        'values': {'ma': 'A', 'mb': 'B', 'mc': 'C', 'me': 'E'},
      }
    };

    test('first another used-again kind is tried', () {
      final r = game(['d'], extra: marked(['a', 'b', 'c', 'e']), fields: mark, kind: const {
        'values': {'a': 'A', 'b': 'B', 'c': 'C', 'd': 'D', 'e': 'E'}
      });
      final kind = r.registry.byId('kind')!;
      for (int i = 0; i < 20; i++) {
        final board = r.assembler.makeBoard(BoardContext(
            dimension: kind, tested: const {'a': 0.0, 'b': 0.2, 'c': 0.5, 'd': 1.0}))!;
        final four = {for (final x in board.groups) x.value};
        expect(four, {'e', 'a', 'b', 'd'},
            reason: 'e is untested; a, b, c are his worst, but with e they have two answers; '
                'so c gives way to d, and the set still has one answer');
        expect(r.assembler.secondSolution(board.tiles, kind), isNull);
      }
    });

    test('only then does it cost him one more set', () {
      // e and f have four things each, two of one mark and two of another: any set with
      // both can also be sorted by mark. So the two untested kinds cannot come together.
      Map<String, Map<String, dynamic>> halves(String k) => {
            for (int i = 0; i < 4; i++)
              '${k}_${letters[i]}': {
                'name': '$k ${letters[i]}',
                'fields': {'kind': k, 'mark': i < 2 ? 'mx' : 'my'}
              },
          };
      final r = game(const [],
          extra: {...marked(['a', 'b', 'c', 'd']), ...halves('e'), ...halves('f')},
          fields: const {
            'mark': {
              'wording': 'Which mark?',
              'sorts_boards': false,
              'values': {'ma': 'A', 'mb': 'B', 'mc': 'C', 'md': 'D', 'mx': 'X', 'my': 'Y'},
            }
          },
          kind: const {
            'values': {'a': 'A', 'b': 'B', 'c': 'C', 'd': 'D', 'e': 'E', 'f': 'F'}
          });
      final kind = r.registry.byId('kind')!;
      for (int i = 0; i < 20; i++) {
        final board = r.assembler.makeBoard(
            BoardContext(dimension: kind, tested: const {'a': 0.5, 'b': 0.5, 'c': 0.5, 'd': 0.5}))!;
        final four = {for (final x in board.groups) x.value};
        expect(four.intersection({'e', 'f'}), hasLength(1),
            reason: 'one untested kind now and the other in one more set: never two answers');
        expect(r.assembler.secondSolution(board.tiles, kind), isNull);
      }
    });

    test('a kind that fits no clean set does not send him round in a ring', () async {
      // e with any three of a, b, c, d can also be sorted by one of four other fields;
      // a, b, c, d by themselves cannot. So e can never be shown.
      const others = {'m1': 'abc', 'm2': 'abd', 'm3': 'acd', 'm4': 'bcd'};
      final things = <String, Map<String, dynamic>>{
        for (final k in ['a', 'b', 'c', 'd', 'e'])
          for (int i = 0; i < 6; i++)
            '${k}_${letters[i]}': {
              'name': '$k ${letters[i]}',
              'fields': {
                'kind': k,
                for (final m in others.entries)
                  if (k == 'e' || m.value.contains(k)) m.key: k,
              }
            },
      };
      final r = game(const [], extra: things, fields: {
        for (final m in others.keys)
          m: {
            'wording': 'Which $m?',
            'sorts_boards': false,
            'values': {for (final k in '${others[m]}e'.split('')) k: k.toUpperCase()},
          }
      }, kind: const {
        'values': {'a': 'A', 'b': 'B', 'c': 'C', 'd': 'D', 'e': 'E'}
      });
      final g = await start(r);
      expect(shown(g), {'a', 'b', 'c', 'd'});
      solve(g);
      expect(g.progress.lines, contains('seed'), reason: 'e is untested, so the set is tried once more');
      g.goNext();
      expect(shown(g), {'a', 'b', 'c', 'd'}, reason: 'no clean set holds e');
      solve(g);
      expect(g.progress.lines, isNot(contains('seed')), reason: 'it tested nothing new: not offered again');
    });
  });

  group('in between', () {
    Map<String, Map<String, dynamic>> between(Object value, [int count = 4]) => {
          for (int i = 0; i < count; i++)
            'x_${letters[i]}': {
              'name': 'x ${letters[i]}',
              'fields': {'kind': value}
            },
        };

    test('a thing that lists two answers, or is marked "depends", is in between', () {
      final listed = Entity.fromJson('rain', {
        'name': 'Rain',
        'fields': {
          'kind': ['a', 'b']
        }
      });
      final debated = Entity.fromJson('virus', {
        'name': 'Virus',
        'fields': {'kind': 'depends'}
      });
      expect(listed.valueFor('kind'), Dimension.inBetween);
      expect(listed.sidesOf('kind'), ['a', 'b']);
      expect(debated.valueFor('kind'), Dimension.inBetween);
      expect(debated.sidesOf('kind'), isEmpty);
      final kind = game(['a', 'b', 'c', 'd']).registry.byId('kind')!;
      expect(kind.label(Dimension.inBetween), 'In between');
      expect(kind.arity, 4, reason: 'it is not one of the answers');
      expect(kind.kinds, ['a', 'b', 'c', 'd']);
    });

    test('fewer than four such things stay off every set, as before', () async {
      final sets = await rounds(game(['a', 'b', 'c', 'd'], extra: between(const ['a', 'b'], 3)));
      expect(sets, hasLength(1));
      expect(sets.single, {'a', 'b', 'c', 'd'});
    });

    test('four of them are a group of their own, after the kinds they lie between', () async {
      final g = await start(game(['a', 'b', 'c', 'd'], extra: between(const ['a', 'b'])));
      expect(shown(g), {'a', 'b', 'c', 'd'}, reason: 'not before he knows both sides');
      solve(g);
      expect(g.progress.lines.first, 'seed');
      g.goNext();
      expect(shown(g), contains(Dimension.inBetween));
      final group = g.board!.groups.singleWhere((x) => x.value == Dimension.inBetween);
      expect(group.label, 'In between');
      expect(group.items.every((e) => e.id.startsWith('x_')), isTrue);
      solve(g);
      expect(g.progress.groups[Dimension.inBetween]!.found, 1);
      expect(g.progress.lines, isNot(contains('seed')));
      expect(g.progress.lines, isNot(contains(Dimension.inBetween)), reason: 'nothing lies inside it');

      // on the web it is tied to the kinds it lies between: a bridge between branches
      final knot = g.web.singleWhere((n) => n.id == Dimension.inBetween);
      expect(knot.parent, 'seed');
      expect(knot.between, unorderedEquals(['a', 'b']));
    });

    test('things nobody agrees about lie between all the kinds', () async {
      final g = await start(game(['a', 'b', 'c', 'd'], extra: between('depends')));
      solve(g);
      g.goNext();
      expect(shown(g), contains(Dimension.inBetween));
      solve(g);
      expect(g.web.singleWhere((n) => n.id == Dimension.inBetween).between,
          unorderedEquals(['a', 'b', 'c', 'd']));
    });

    test('where a side has a set of its own, he must have played it first', () async {
      // kind a has sixteen things sorted four ways by "sort": a set of its own
      final inside = <String, Map<String, dynamic>>{
        for (int s = 0; s < 4; s++)
          for (int i = 0; i < 4; i++)
            'a_s$s$i': {
              'name': 'a $s $i',
              'fields': {'kind': 'a', 'sort': 's$s'}
            },
      };
      final r = game(['b', 'c', 'd'], extra: {...inside, ...between(const ['a', 'b'])}, fields: const {
        'sort': {
          'wording': 'Which sort?',
          'values': {'s0': 'S0', 's1': 'S1', 's2': 'S2', 's3': 'S3'},
        }
      }, kind: const {
        'values': {'a': 'A', 'b': 'B', 'c': 'C', 'd': 'D'}
      });
      final g = await start(r);
      solve(g, ['a']);
      expect(g.progress.lines, isNot(contains('seed')), reason: 'he has found a, but not been inside it');
      expect(g.nextStep!.id, 'a');
      g.goNext();
      solve(g);
      expect(g.progress.lines, contains('seed'), reason: 'now he knows both sides');
      for (int i = 0; i < 4 && g.nextStep!.id != 'seed'; i++) {
        g.goNext();
        solve(g);
      }
      g.goNext();
      expect(g.pathLabels, ['Everything']);
      expect(shown(g), contains(Dimension.inBetween));
    });

    test('it never makes up the number: three kinds and "in between" are no set', () {
      final r = game(['a', 'b', 'c'], extra: between(const ['a', 'b']), kind: const {
        'values': {'a': 'A', 'b': 'B', 'c': 'C', 'd': 'D'}
      });
      expect(r.assembler.boardableDimensions(const []), isEmpty);
      expect(r.assembler.makeBoard(const BoardContext()), isNull);
    });
  });

  test('the end of a branch is no line to follow, and the web knows it', () async {
    final g = await start(game(['a', 'b', 'c', 'd'], ends: const {
      'b': {'on': '2026-11-24', 'why': 'only five such things have a page of their own'}
    }));
    solve(g, ['b', 'a']);
    expect(g.didWell(g.board!.groups.firstWhere((x) => x.value == 'b')), isTrue);
    expect(g.progress.lines, isNot(contains('b')), reason: 'nothing lies below it');
    expect(g.progress.lines.first, 'a');
    final web = {for (final n in g.web) n.id: n};
    expect(web['b']!.end, isTrue);
    expect(web['a']!.end, isFalse);
    expect(g.registry.ends['b'], contains('only five'));
  });

  testWidgets('the web shows a leaf on the end of a branch, and ties "in between" to both sides', (tester) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final g = await start(game(['a', 'b', 'c', 'd'], extra: {
      for (int i = 0; i < 4; i++)
        'x_${letters[i]}': {
          'name': 'x ${letters[i]}',
          'fields': {
            'kind': ['a', 'c']
          }
        },
    }, kind: const {
      'in_between': {'label': 'Hard to place'},
    }, ends: const {
      'b': 'only five such things have a page of their own'
    }));
    solve(g);
    g.goNext();
    solve(g);
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<EngineProvider>.value(value: g, child: const WebScreen()),
    ));
    for (int i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('web-end-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('web-end-a')), findsNothing);
    expect(find.text('Hard to place'), findsOneWidget, reason: 'the dictionary may name the group itself');
    expect(find.textContaining('the end of a branch'), findsOneWidget);
    expect(find.textContaining('in between, tied to both sides'), findsOneWidget);
    final m = measureWeb(g.web);
    expect(m.ends, 5, reason: 'four kinds and the group in between');
  });
}
