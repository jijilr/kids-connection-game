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

  testWidgets('the thumbnails are centred and grow with the screen, on any size', (tester) async {
    Future<List<Rect>> thumbnailsOn(Size screen) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      await pump(tester, (e) => const EntityMedia(emoji: '🙂'));
      expect(tester.takeException(), isNull, reason: 'nothing overflows at $screen');
      return [for (final e in animals) tester.getRect(find.byKey(ValueKey('solved-${e.id}')))];
    }

    addTearDown(tester.view.reset);
    final phone = await thumbnailsOn(const Size(360, 720));
    final tablet = await thumbnailsOn(const Size(820, 1180));
    final small = await thumbnailsOn(const Size(300, 520));
    for (final rects in [phone, tablet, small]) {
      final screenWidth = rects == phone ? 360.0 : rects == tablet ? 820.0 : 300.0;
      // centred: the space left of the first picture equals the space right of the last
      expect(rects.first.left, closeTo(screenWidth - rects.last.right, 0.5));
      expect(rects.every((r) => r.width == rects.first.width && r.height == r.width), isTrue);
    }
    expect(phone.first.width, greaterThan(64), reason: 'larger than the first version on a phone');
    expect(tablet.first.width, greaterThan(phone.first.width));
    expect(small.first.width, lessThan(phone.first.width));
    // on a phone the four pictures use nearly the whole width of the bar
    expect(phone.last.right - phone.first.left, greaterThan(360 * 0.75));
  });

  test('the size follows the width until the height would be too much', () {
    expect(thumbnailSize(308, 800, 4), closeTo((308 - 24) / 4, 0.01)); // a tall phone: the width decides
    expect(thumbnailSize(308, 720, 4), closeTo((720 - 230) / 4 - 56, 0.01)); // a shorter phone: the height decides
    expect(thumbnailSize(1200, 700, 4), closeTo((700 - 230) / 4 - 56, 0.01)); // a wide, short window: the height decides
    expect(thumbnailSize(120, 400, 4), 40); // never too small to see
    expect(thumbnailSize(5000, 5000, 4), 160); // never absurdly large
  });

  testWidgets('a group with no pictures at all still lists its names', (tester) async {
    await pump(tester, (e) => const EntityMedia());
    expect(find.textContaining('Lion'), findsOneWidget);
    expect(find.byKey(const ValueKey('solved-lion')), findsNothing);
  });
}
