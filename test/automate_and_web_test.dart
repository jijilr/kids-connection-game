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

/// Two things the owner asked for on 24 Nov 2026.
/// Automate: "dig deeper is not a choice for the user. this is a test feature... the dig
/// deeper is done by the app... keep an 'automate' button on the top. automate is what the
/// app is designed for." So the app chooses the way by default, and the test features
/// show only when Automate is switched off.
/// The web: "an interface to see the web diagram of mastery so far".
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
  tester.view.physicalSize = const Size(600, 960);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: ChangeNotifierProvider<EngineProvider>.value(value: g, child: screen),
  ));
  await tester.pump();
}

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  final day = DateTime(2026, 11, 24, 10);

  test('the app chooses the way unless Automate was switched off on this device', () async {
    final store = MemoryProgressStore();
    final g = EngineProvider(repo: repo(1), random: Roll(), progressStore: store, clock: () => day);
    await g.init();
    expect(g.automate, isTrue, reason: 'what the app is designed for');
    await g.setAutomate(false);
    final later = EngineProvider(repo: repo(2), random: Roll(), progressStore: store, clock: () => day);
    await later.init();
    expect(later.automate, isFalse, reason: 'the switch is kept on the device');
  });

  testWidgets('with Automate on, a finished set offers no choice: one button, Next', (tester) async {
    final g = EngineProvider(repo: repo(3), random: Roll(), clock: () => day);
    await g.init();
    await show(tester, g, const EngineScreen());
    expect(find.text('Auto'), findsOneWidget);
    solve(g, ['animal']);
    await settle(tester);
    expect(find.textContaining('Dig deeper'), findsNothing, reason: 'digging deeper is the app\'s work, not his choice');
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Back'), findsNothing);
    expect(find.byTooltip('New board'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('next')));
    await settle(tester);
    expect(g.pathLabels.last, 'Animals', reason: 'the app followed the group he did best');
    expect(find.text('Back'), findsNothing);
  });

  testWidgets('with Automate switched off, the test features show', (tester) async {
    final g = EngineProvider(repo: repo(4), random: Roll(), clock: () => day);
    await g.init();
    await show(tester, g, const EngineScreen());
    await tester.tap(find.byKey(const ValueKey('automate')));
    await tester.pump();
    expect(g.automate, isFalse);
    expect(find.text('Test'), findsOneWidget);
    expect(find.byTooltip('New board'), findsOneWidget);
    solve(g, ['animal']);
    await settle(tester);
    expect(find.text('Dig deeper'), findsWidgets, reason: 'on each found group that has a set inside');
    expect(find.text('Dig deeper: Animals'), findsOneWidget);
  });

  test('the web holds the first set and every group he has found, joined to where it was found', () async {
    final g = EngineProvider(repo: repo(5), random: Roll(), clock: () => day);
    await g.init();
    expect(g.web.map((n) => n.id), ['seed'], reason: 'nothing he has not met is in it');

    // a wrong guess that takes in plants and nature, then the whole set
    final groups = {for (final x in g.board!.groups) x.value: x};
    for (final e in [...groups['plant']!.items.take(2), ...groups['nature_not_alive']!.items.take(2)]) {
      g.toggle(e);
    }
    g.submit();
    solve(g, ['animal']);
    final web = {for (final n in g.web) n.id: n};
    expect(web.keys, unorderedEquals(['seed', 'animal', 'plant', 'nature_not_alive', 'made_by_people']));
    expect(web['seed']!.isStart, isTrue);
    expect(web['animal']!.parent, 'seed');
    expect(web['animal']!.label, 'Animals');
    expect((web['animal']!.found, web['animal']!.clean), (1, 1));
    expect((web['plant']!.found, web['plant']!.clean), (1, 0), reason: 'found, but after a wrong guess');
    expect(web['animal']!.line, isTrue, reason: 'the app follows it next');
    expect(web['plant']!.line, isFalse);
    expect(web['animal']!.picture?.art, isNotNull, reason: 'a picture, for a child who cannot read');

    // deeper: what he finds inside Animals hangs from Animals
    g.goNext();
    solve(g);
    final deeper = g.web.where((n) => n.parent == 'animal').toList();
    expect(deeper, hasLength(4));
    expect(deeper.every((n) => n.id.startsWith('animal/') && n.found == 1), isTrue);
    expect(g.web.singleWhere((n) => n.id == 'animal').line, isTrue,
        reason: 'two kinds of animal are still untested: its set comes once more');
    g.goNext();
    solve(g);
    expect(g.web.where((n) => n.parent == 'animal'), hasLength(6), reason: 'every kind of animal that can be shown');
    expect(g.web.singleWhere((n) => n.id == 'animal').line, isFalse, reason: 'its set is played out: no longer a line');
  });

  testWidgets('the web screen draws each group once, and says so when there is nothing yet', (tester) async {
    final g = EngineProvider(repo: repo(6), random: Roll(), clock: () => day);
    await g.init();
    await show(tester, g, const WebScreen());
    expect(find.byKey(const ValueKey('web-empty')), findsOneWidget);

    solve(g, ['animal']);
    g.goNext();
    solve(g);
    await tester.pump();
    expect(find.byKey(const ValueKey('web-empty')), findsNothing);
    for (final n in g.web) {
      expect(find.byKey(ValueKey('web-${n.id}')), findsOneWidget, reason: n.id);
    }
    expect(find.text('Animals'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // every knot has its own place, and a group stands further out than the set it was found in
    final layout = WebLayout(g.web, 700);
    expect(layout.at.values.toSet().length, g.web.length);
    final centre = layout.at['seed']!;
    for (final n in g.web.where((n) => n.parent == 'animal')) {
      expect((layout.at[n.id]! - centre).distance, greaterThan((layout.at['animal']! - centre).distance));
    }
  });

  testWidgets('the web opens from the button at the top of the game', (tester) async {
    final g = EngineProvider(repo: repo(7), random: Roll(), clock: () => day);
    await g.init();
    await show(tester, g, const EngineScreen());
    solve(g);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('web')));
    await settle(tester);
    expect(find.text('What he has found'), findsOneWidget);
    expect(find.byKey(const ValueKey('web-animal')), findsOneWidget);
  });
}
