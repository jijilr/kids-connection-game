import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connections_game/models/entity.dart';
import 'package:connections_game/services/media.dart';
import 'package:connections_game/widgets/solved_group_bar.dart';

void main() {
  final animals = [
    for (final name in ['Lion', 'Hen', 'Goldfish', 'Butterfly'])
      Entity(id: name.toLowerCase(), name: name, fields: const {'kind_of_thing': 'animal'}),
  ];

  Future<List<String>> pump(WidgetTester tester, EntityMedia Function(Entity) mediaFor,
      {VoidCallback? onDescend}) async {
    final said = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SolvedGroupBar(
          label: 'Animals',
          items: animals,
          mediaFor: mediaFor,
          color: Colors.teal,
          onSay: (e) => said.add(e.label),
          onDescend: onDescend,
        ),
      ),
    ));
    return said;
  }

  testWidgets('a solved group shows four pictures, not names, and a tap says the name',
      (tester) async {
    var descended = 0;
    final said = await pump(tester, (e) => const EntityMedia(emoji: '🙂'),
        onDescend: () => descended++);

    expect(find.text('ANIMALS'), findsOneWidget);
    for (final e in animals) {
      expect(find.byKey(ValueKey('solved-${e.id}')), findsOneWidget);
      expect(find.textContaining(e.name), findsNothing, reason: 'he cannot read yet');
    }

    await tester.tap(find.byKey(const ValueKey('solved-goldfish')));
    expect(said, ['Goldfish']);
    expect(descended, 0, reason: 'a tap on a picture says its name; it does not dig deeper');

    await tester.tap(find.text('ANIMALS'));
    expect(descended, 1);
  });

  testWidgets('a group with no pictures at all still lists its names', (tester) async {
    await pump(tester, (e) => const EntityMedia());
    expect(find.textContaining('Lion'), findsOneWidget);
    expect(find.byKey(const ValueKey('solved-lion')), findsNothing);
  });
}
