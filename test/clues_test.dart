import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:connections_game/models/dimension.dart';
import 'package:connections_game/models/entity.dart';
import 'package:connections_game/models/game_settings.dart';
import 'package:connections_game/models/group_words.dart';
import 'package:connections_game/providers/engine_provider.dart';
import 'package:connections_game/services/content_repository.dart';
import 'package:connections_game/services/media.dart';

/// Clues and explanations (the owner's ruling of 7 Oct 2026). A clue leads the child
/// toward a group without naming its members, climbs a ladder, and never costs a star.
/// An explanation is shown and spoken when a group is found. Both are written for the
/// group, not for a board.
Map<String, dynamic> readData(String file) =>
    jsonDecode(File('Assets/data/$file').readAsStringSync()) as Map<String, dynamic>;

late List<Entity> entities;
late DimensionRegistry registry;
late GroupWordsBook words;

ContentRepository repo(int seed, {GroupWordsBook? book}) {
  final assets = Directory('Assets')
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path.replaceAll('\\', '/'))
      .toSet();
  return ContentRepository.fromData(entities, registry, GameSettings.fromJson(readData('settings.json')),
      random: Random(seed),
      media: MediaResolver.fromJson(assets, readData('pictures.json')),
      words: book ?? words);
}

void find(EngineProvider g, String value) {
  for (final e in g.board!.groups.singleWhere((x) => x.value == value).items) {
    g.toggle(e);
  }
  g.submit();
}

void main() {
  setUpAll(() {
    entities = ContentRepository.thingsFromJson(readData('things.json'));
    registry = DimensionRegistry.fromJson(readData('dictionary.json'));
    words = GroupWordsBook.fromJson(readData('groups.json'));
  });

  test('the words as shipped: ladders of three, clips that exist, and no clue names a member', () {
    final groups = readData('groups.json')['groups'] as Map<String, dynamic>;
    expect(groups, isNotEmpty);
    groups.forEach((key, value) {
      final field = key.split('=').first, wanted = key.split('=').last;
      final clues = (value['clues'] as List).cast<Map<String, dynamic>>();
      expect(clues.isEmpty || clues.length >= 3, isTrue, reason: '$key: a ladder has at least three clues');
      final members = entities.where((e) => e.valueFor(field) == wanted).map((e) => e.label.toLowerCase());
      for (final clue in clues) {
        final said = ' ${(clue['text'] as String).toLowerCase().replaceAll(RegExp('[^a-z ]'), ' ')} ';
        for (final name in members) {
          expect(said.contains(' $name '), isFalse, reason: '$key: the clue "${clue['text']}" names $name');
        }
        expect(File(clue['audio'] as String).existsSync(), isTrue, reason: '$key: ${clue['audio']}');
      }
      final told = value['explanation'] as Map<String, dynamic>?;
      if (told != null) {
        final sentences = RegExp(r'[.!?]+(\s|$)').allMatches(told['text'] as String).length;
        expect(sentences, inInclusiveRange(2, 3), reason: '$key: two or three sentences');
        expect(File(told['audio'] as String).existsSync(), isTrue, reason: '$key: ${told['audio']}');
      }
    });
    // most of the groups a child can meet have their words by now
    expect(groups.values.where((g) => (g['clues'] as List).length >= 3).length, greaterThan(40));
  });

  test('clues climb a ladder for one group, follow what he is working on, and never cost a star', () async {
    final g = EngineProvider(repo: repo(11), random: Random(11));
    await g.init();
    expect(g.hasClue, isTrue);
    expect(g.clue, isNull);

    // nothing chosen: the ladder starts on the first group still to be found, at its first step
    final first = g.board!.groups.firstWhere((x) => words.of(x.dimId, x.value)!.clues.isNotEmpty);
    final ladder = words.of(first.dimId, first.value)!.clues;
    expect(g.nextClue()!.text, ladder[0].text);
    expect(g.nextClue()!.text, ladder[1].text);
    expect(g.nextClue()!.text, ladder[2].text);
    expect(g.nextClue()!.text, ladder.last.text, reason: 'the last clue is repeated, never something more');

    // he starts on another group: the next clue is for that one, from its first step
    final other = g.board!.groups.firstWhere((x) => x.value != first.value);
    g.toggle(other.items[0]);
    g.toggle(other.items[1]);
    expect(g.nextClue()!.text, words.of(other.dimId, other.value)!.clues[0].text);
    g.deselectAll();

    // clues cost nothing: no mistake, and three stars after a clean solve
    expect(g.mistakes, 0);
    expect(g.cluesUsed, 5);
    for (final grp in [...g.board!.groups]) {
      find(g, grp.value);
    }
    expect(g.stars, 3);
    expect(g.hasClue, isFalse, reason: 'nothing left to hint at');
  });

  test('when a group is found its explanation is the one written for that group', () async {
    final g = EngineProvider(repo: repo(12), random: Random(12));
    await g.init();
    expect(g.explanation, isNull);
    final grp = g.board!.groups.first;
    g.nextClue();
    find(g, grp.value);
    expect(g.explanation?.text, words.of(grp.dimId, grp.value)?.explanation?.text);
    expect(g.clue, isNull, reason: 'the clue for a group goes when the group is found');
    // a fresh board starts with neither
    g.newBoard();
    expect(g.explanation, isNull);
    expect(g.clue, isNull);
    expect(g.cluesUsed, 0);
  });

  test('a group with no words written simply has no clue and no explanation', () async {
    final g = EngineProvider(repo: repo(13, book: const GroupWordsBook.empty()), random: Random(13));
    await g.init();
    expect(g.hasClue, isFalse);
    expect(g.nextClue(), isNull);
    find(g, g.board!.groups.first.value);
    expect(g.explanation, isNull);
    expect(g.solved, hasLength(1));
  });

  test('the same words serve a group on whatever board it appears', () {
    // the words are keyed by the field and its value alone: no board, no circle, no tile
    final book = GroupWordsBook.fromJson({
      'groups': {
        'part_we_eat=leaves': {
          'clues': [
            {'text': 'one', 'audio': null},
            {'text': 'two', 'audio': null},
            {'text': 'three', 'audio': null}
          ],
          'explanation': {'text': 'Why. A fact.', 'audio': 'x.mp3'}
        },
        'broken': 'nonsense'
      }
    });
    expect(book.of('part_we_eat', 'leaves')!.clues.map((c) => c.text), ['one', 'two', 'three']);
    expect(book.of('part_we_eat', 'leaves')!.explanation!.audio, 'x.mp3');
    expect(book.of('part_we_eat', 'fruit'), isNull);
    expect(book.length, 1);
  });
}
