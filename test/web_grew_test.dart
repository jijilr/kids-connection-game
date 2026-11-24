import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:connections_game/models/dimension.dart';
import 'package:connections_game/models/game_settings.dart';
import 'package:connections_game/providers/engine_provider.dart';
import 'package:connections_game/screens/engine_screen.dart';
import 'package:connections_game/screens/web_screen.dart';
import 'package:connections_game/services/content_repository.dart';
import 'package:connections_game/services/media.dart';
import 'package:connections_game/services/progress.dart';

/// The owner's two measures, and "your web grew" (24 Nov 2026).
/// Breadth and depth are counted on his own web, not on a list of subjects of ours:
/// breadth is how many ends the web has, depth how many steps lead to an end.
/// The knots he has not been shown before light up when the web opens, and after a few
/// sets in one sitting the web opens by itself.
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
      media: MediaResolver.fromJson(assets, readData('pictures.json')));
}

class Roll implements Random {
  @override
  double nextDouble() => 0.1;
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

Future<void> show(WidgetTester tester, EngineProvider g, Widget screen) async {
  tester.view.physicalSize = const Size(700, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: ChangeNotifierProvider<EngineProvider>.value(value: g, child: screen),
  ));
  await tester.pump();
}

Future<void> settle(WidgetTester tester, [int quarters = 8]) async {
  for (int i = 0; i < quarters; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  final day = DateTime(2026, 11, 24, 10);

  test('breadth is the number of ends of the web, depth the steps that lead to them', () {
    const web = [
      WebNode('seed', 'Everything', null),
      WebNode('a', 'A', 'seed', found: 2),
      WebNode('a/x', 'X', 'a', found: 1),
      WebNode('a/y', 'Y', 'a', found: 1),
      WebNode('b', 'B', 'seed', found: 1),
    ];
    final m = measureWeb(web);
    expect(m.ends, 3, reason: 'X, Y and B: A is no end, something was found beyond it');
    expect(m.averageDepth, closeTo(5 / 3, 0.001));
    expect(m.deepest, 2);
    final nothing = measureWeb(const [WebNode('seed', 'Everything', null)]);
    expect((nothing.ends, nothing.averageDepth, nothing.deepest), (0, 0.0, 0));
    // no list of subjects is consulted: the same shape under other names measures the same
    final other = measureWeb(const [
      WebNode('seed', 'Start', null),
      WebNode('p', 'P', 'seed'),
      WebNode('p/q', 'Q', 'p'),
      WebNode('p/r', 'R', 'p'),
      WebNode('s', 'S', 'seed'),
    ]);
    expect((other.ends, other.deepest), (3, 2));
  });

  test('the measures and the new knots follow his play', () async {
    final store = MemoryProgressStore();
    final g = EngineProvider(repo: repo(1), random: Roll(), progressStore: store, clock: () => day);
    await g.init();
    expect(g.newKnots, isEmpty);
    solve(g, ['animal']);
    expect(g.newKnots, hasLength(4));
    var m = measureWeb(g.web);
    expect((m.ends, m.averageDepth, m.deepest), (4, 1.0, 1));

    g.markWebSeen();
    expect(g.newKnots, isEmpty, reason: 'he has been shown them');
    g.goNext();
    solve(g);
    expect(g.newKnots, hasLength(4), reason: 'what he found inside Animals is new');
    expect(g.newKnots.every((id) => id.startsWith('animal/')), isTrue);
    m = measureWeb(g.web);
    expect(m.ends, 7, reason: 'the three other first groups, and four inside Animals');
    expect(m.averageDepth, closeTo(11 / 7, 0.001));
    expect(m.deepest, 2);

    // what he has been shown is kept between visits
    final file = jsonDecode(g.progress.toFileText()) as Map<String, dynamic>;
    expect(file['web_seen'], hasLength(4));
    expect(Progress.fromJson(file).webSeen, g.progress.webSeen);
  });

  test('after four sets in one sitting it is time to show him his web, once', () async {
    final g = EngineProvider(repo: repo(2), random: Roll(), clock: () => day);
    await g.init();
    for (int set = 1; set <= 3; set++) {
      solve(g);
      expect(g.webMomentDue, isFalse, reason: 'after set $set');
      g.goNext();
    }
    solve(g);
    expect(g.webMomentDue, isTrue);
    g.webMomentShown();
    expect(g.webMomentDue, isFalse, reason: 'once');
  });

  testWidgets('the new knots light up, and the two measures are told to the grown-up', (tester) async {
    final g = EngineProvider(repo: repo(3), random: Roll(), clock: () => day);
    await g.init();
    solve(g, ['animal']);
    await show(tester, g, const WebScreen());
    expect(find.byKey(const ValueKey('web-grew')), findsOneWidget);
    expect(find.text('Your web grew: 4 new'), findsOneWidget);
    expect(find.textContaining('Breadth'), findsOneWidget);
    expect(find.textContaining('4 ends'), findsOneWidget);
    expect(find.textContaining('1.0 steps on average, deepest 1'), findsOneWidget);
    expect(find.textContaining('not how much he knows'), findsOneWidget);

    // part of the way through: the last new knot has not come in yet, the first has
    await tester.pump(const Duration(milliseconds: 500));
    final ids = g.web.where((n) => !n.isStart).map((n) => n.id).toList();
    double shownOf(String id) =>
        tester.widget<Opacity>(find.descendant(of: find.byKey(ValueKey('web-$id')), matching: find.byType(Opacity))).opacity;
    expect(shownOf(ids.first), greaterThan(shownOf(ids.last)));
    await settle(tester, 16);
    for (final id in ids) {
      expect(shownOf(id), 1.0, reason: '$id is fully there at the end');
    }
    expect(g.newKnots, isEmpty, reason: 'he has now been shown them');
    expect(tester.takeException(), isNull);

    // the next time nothing is new: no banner, and nothing springs in
    await show(tester, g, const SizedBox());
    await show(tester, g, const WebScreen());
    expect(find.byKey(const ValueKey('web-grew')), findsNothing);
  });

  testWidgets('after four sets the web opens by itself before the next set, and its button leads on', (tester) async {
    final g = EngineProvider(repo: repo(4), random: Roll(), clock: () => day);
    await g.init();
    await show(tester, g, const EngineScreen());
    for (int set = 1; set <= 3; set++) {
      solve(g);
      g.goNext();
    }
    solve(g);
    await settle(tester);
    expect(find.text('+13'), findsNothing); // the mark on the web button counts what is new, whatever it is
    await tester.tap(find.byKey(const ValueKey('next')));
    await settle(tester);
    expect(find.byKey(const ValueKey('web-grew')), findsOneWidget, reason: 'his web, before the next set');
    expect(find.byKey(const ValueKey('web-next')), findsOneWidget);
    await settle(tester, 40);
    await tester.tap(find.byKey(const ValueKey('web-next')));
    await settle(tester);
    expect(find.byKey(const ValueKey('web-next')), findsNothing);
    expect(g.boardFinished, isFalse, reason: 'the next set has begun');
    expect(g.board!.tiles, hasLength(16));
  });

  // The child's own way into the web: a small round picture of it beside Next, on the card
  // that ends every set (the owner's word of 24 Nov 2026). He cannot read a button's name.
  for (final screen in const [Size(700, 1000), Size(360, 640)]) {
    testWidgets('a small picture of his web stands beside Next and opens the web, at ${screen.width.round()} wide',
        (tester) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final g = EngineProvider(repo: repo(6), random: Roll(), clock: () => day);
      await g.init();
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<EngineProvider>.value(value: g, child: const EngineScreen()),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('web-mini')), findsNothing, reason: 'not while a set is being played');
      solve(g, ['animal']);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'nothing overflows');
      final mini = tester.getRect(find.byKey(const ValueKey('web-mini')));
      final next = tester.getRect(find.byKey(const ValueKey('next')));
      final list = tester.getRect(find.byType(SingleChildScrollView));
      expect(mini.bottom, lessThanOrEqualTo(list.bottom), reason: 'on the screen, like Next');
      expect(next.bottom, lessThanOrEqualTo(list.bottom));
      expect(mini.width, greaterThanOrEqualTo(48), reason: 'large enough for a small finger');
      expect(find.text('+4'), findsWidgets, reason: 'marked: four groups are new on his web');

      await tester.tap(find.byKey(const ValueKey('web-mini')));
      await settle(tester, 16);
      expect(find.text('What he has found'), findsOneWidget);
      expect(find.byKey(const ValueKey('web-next')), findsNothing, reason: 'he came to look; the arrow at the top goes back');
      await tester.pageBack();
      await settle(tester);
      expect(find.byKey(const ValueKey('next')), findsOneWidget, reason: 'back on the card, Next still there');
      expect(find.text('+4'), findsNothing, reason: 'he has seen them now');
    });
  }
}
