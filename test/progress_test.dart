import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connections_game/models/dimension.dart';
import 'package:connections_game/models/game_settings.dart';
import 'package:connections_game/providers/engine_provider.dart';
import 'package:connections_game/services/content_repository.dart';
import 'package:connections_game/services/media.dart';
import 'package:connections_game/services/progress.dart';
import 'package:connections_game/widgets/grown_up_panel.dart';

/// Saved progress: which boards were opened and solved on this device, kept between
/// visits, and saved as a file the job can read.
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

void solve(EngineProvider g) {
  for (final grp in g.board!.groups) {
    for (final e in grp.items) {
      g.toggle(e);
    }
    g.submit();
  }
}

void main() {
  final noon = DateTime.utc(2026, 10, 7, 12);

  test('a board is named by the path that leads to it, as the job names circles', () {
    expect(Progress.boardId(const []), 'seed');
    expect(Progress.boardId(const [('kind_of_thing', 'animal')]), 'animal');
    expect(
        Progress.boardId(const [('kind_of_thing', 'animal'), ('kind_of_animal', 'dinosaur')]),
        'animal/dinosaur');
  });

  test('opening and solving boards is recorded, and kept between visits', () async {
    final store = MemoryProgressStore();
    final g = EngineProvider(repo: repo(3), random: Random(3), progressStore: store, clock: () => noon);
    await g.init();
    expect(g.progress.boards['seed']!.opened, 1);
    expect(g.progress.boards['seed']!.solved, 0);

    solve(g);
    expect(g.progress.boards['seed']!.solved, 1);
    g.descendInto(g.board!.groups.singleWhere((x) => x.value == 'animal'));
    expect(g.progress.boards['animal']!.opened, 1);
    expect(g.progress.lastBoard, 'animal');
    expect(g.progress.played, containsAll(['seed', 'animal']));

    // a later visit, on the same device
    final again = EngineProvider(repo: repo(4), random: Random(4), progressStore: store, clock: () => noon);
    await again.init();
    expect(again.progress.boards['seed']!.opened, 2);
    expect(again.progress.boards['seed']!.solved, 1);
    expect(again.progress.boards['animal']!.opened, 1);
  });

  test('the saved file holds boards and counts, and nothing about the child', () {
    final progress = Progress()
      ..opened('seed', noon)
      ..solved('seed', noon)
      ..opened('made_by_people/vehicle', noon);
    final file = jsonDecode(progress.toFileText()) as Map<String, dynamic>;
    expect(file.keys, unorderedEquals(['what', 'version', 'updated', 'last_board', 'boards']));
    expect(file['version'], 1);
    expect(file['last_board'], 'made_by_people/vehicle');
    expect(file['boards']['seed'], {'opened': 1, 'solved': 1, 'last': '2026-10-07T12:00:00.000Z'});

    final back = Progress.fromJson(file);
    expect(back.played, unorderedEquals(['seed', 'made_by_people/vehicle']));
    expect(back.boards['seed']!.solved, 1);
  });

  test('a broken or empty saved copy starts afresh instead of stopping the game', () {
    expect(Progress.fromJson(const {}).boards, isEmpty);
    expect(Progress.fromJson(const {'boards': 'nonsense', 'updated': 'x'}).boards, isEmpty);
  });

  testWidgets('the grown-up panel lists the boards and saves the file', (tester) async {
    final progress = Progress()
      ..opened('seed', noon)
      ..solved('seed', noon)
      ..opened('animal', noon);
    String? savedName, savedText;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GrownUpPanel(
          progress: progress,
          saveFile: (name, text) {
            savedName = name;
            savedText = text;
            return true;
          },
        ),
      ),
    ));
    expect(find.text('seed: opened 1, solved 1'), findsOneWidget);
    expect(find.text('animal: opened 1, solved 0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('progress-save')));
    await tester.pump();
    expect(savedName, 'progress.json');
    expect((jsonDecode(savedText!) as Map)['boards'], contains('animal'));
    expect(find.text('Saved as progress.json.'), findsOneWidget);
  });
}
