import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:connections_game/models/dimension.dart';
import 'package:connections_game/models/game_settings.dart';
import 'package:connections_game/models/group_words.dart';
import 'package:connections_game/providers/engine_provider.dart';
import 'package:connections_game/screens/engine_screen.dart';
import 'package:connections_game/services/content_repository.dart';
import 'package:connections_game/services/media.dart';
import 'package:connections_game/services/progress.dart';

/// Room for the set on a phone (the owner, 24 Nov 2026, of the explanation: "in my phone
/// this takes away too much vertical space and make it less fun to play... is there a way
/// to keep it minimized, if the user so chooses"; and of "Yes! Plants": "can you show at
/// the center and let it fade away... as this space too can be used better").
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

void guess(EngineProvider g, List<String> ids) {
  g.deselectAll();
  for (final e in g.board!.tiles.where((e) => ids.contains(e.id))) {
    g.toggle(e);
  }
  g.submit();
}

void findGroup(EngineProvider g, String value) =>
    guess(g, [for (final e in g.board!.groups.singleWhere((x) => x.value == value).items) e.id]);

Future<void> onAPhone(WidgetTester tester, EngineProvider g) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: ChangeNotifierProvider<EngineProvider>.value(value: g, child: const EngineScreen()),
  ));
  await tester.pump();
}

void main() {
  final day = DateTime(2026, 11, 24, 20);

  testWidgets('the answer to a guess shows over the middle of the set, fades, and takes no room', (tester) async {
    final g = EngineProvider(repo: repo(1), clock: () => day);
    await g.init();
    await g.setWordsSmall(true);
    await onAPhone(tester, g);
    final buttons = find.byKey(const ValueKey('clue-button'));
    final before = tester.getRect(buttons).top;
    expect(find.byKey(const ValueKey('flash')), findsNothing);

    // a wrong guess: two things of one group, two of another
    final a = g.board!.groups[0].items, b = g.board!.groups[1].items;
    guess(g, [a[0].id, a[1].id, b[0].id, b[1].id]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Not quite — try another group.'), findsOneWidget);
    expect(tester.getRect(buttons).top, before, reason: 'no line of its own: the buttons have not moved');
    final shown = tester.getCenter(find.byKey(const ValueKey('flash')));
    expect((shown.dx - 180).abs(), lessThan(2), reason: 'in the middle');
    expect(shown.dy, inInclusiveRange(150, 450));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('flash')), findsNothing, reason: 'it has faded');

    // the same words again are shown afresh
    guess(g, [a[0].id, a[1].id, b[0].id, b[1].id]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Not quite — try another group.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));

    findGroup(g, 'plant');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Yes! Plants'), findsOneWidget);
    expect(tester.getRect(buttons).top, before);
    // it never stands in the way of a touch: a tile under it can still be chosen
    final tile = g.openTiles.first;
    await tester.tapAt(tester.getCenter(find.byKey(ValueKey(tile.id))));
    expect(g.isSelected(tile), isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Yes! Plants'), findsNothing);
    // let the banners of the found groups finish coming in
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the explanation can be kept small, and the choice is remembered', (tester) async {
    final store = MemoryProgressStore();
    final g = EngineProvider(repo: repo(2), progressStore: store, clock: () => day);
    await g.init();
    expect(g.wordsSmall, isFalse, reason: 'shown in full until he chooses otherwise');
    await onAPhone(tester, g);
    final buttons = find.byKey(const ValueKey('clue-button'));
    final free = tester.getRect(buttons).top;

    findGroup(g, 'plant');
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(g.explanation, isNotNull);
    expect(find.byKey(const ValueKey('explanation')), findsOneWidget);
    expect(find.text(g.explanation!.text), findsOneWidget);
    final pushed = tester.getRect(buttons).top;
    expect(tester.getRect(find.byKey(const ValueKey('explanation'))).height, greaterThan(50),
        reason: 'the room it takes on a phone');

    // the small arrow on it puts it away
    await tester.tap(find.byKey(const ValueKey('explanation-small')));
    await tester.pump();
    expect(g.wordsSmall, isTrue);
    expect(find.byKey(const ValueKey('explanation')), findsNothing);
    expect(tester.getRect(buttons).top, pushed, reason: 'the buttons stay; the set has the room');
    expect(tester.getRect(buttons).top, free);
    expect(find.byKey(const ValueKey('explanation-open')), findsOneWidget, reason: 'a small book in the question bar');

    // the next group: still small, by his choice
    findGroup(g, 'animal');
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('explanation')), findsNothing);
    expect(find.byKey(const ValueKey('explanation-open')), findsOneWidget);

    // a touch on the book brings the words back
    await tester.tap(find.byKey(const ValueKey('explanation-open')));
    await tester.pump();
    expect(g.wordsSmall, isFalse);
    expect(find.text(g.explanation!.text), findsOneWidget);
    expect(find.byKey(const ValueKey('explanation-open')), findsNothing);

    // remembered on the device
    await g.setWordsSmall(true);
    final again = EngineProvider(repo: repo(2), progressStore: store, clock: () => day);
    await again.init();
    expect(again.wordsSmall, isTrue);
    // let the banners of the found groups finish coming in
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(tester.takeException(), isNull);
  });
}
