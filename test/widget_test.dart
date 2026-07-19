// Replaces the broken stock counter test. Real engine tests arrive with P3.
import 'package:flutter_test/flutter_test.dart';
import 'package:connections_game/models/entity.dart';

void main() {
  test('Entity namespaced tags: valueFor / isIn / hasTag', () {
    const e = Entity(
      id: 'trex',
      name: 'T-Rex',
      domain: 'animals',
      tags: ['category:dinosaur', 'diet:carnivore', 'extinct'],
    );
    expect(e.valueFor('category'), 'dinosaur');
    expect(e.valueFor('diet'), 'carnivore');
    expect(e.valueFor('habitat'), isNull);
    expect(e.isIn('category', 'dinosaur'), isTrue);
    expect(e.isIn('category', 'reptile'), isFalse);
    expect(e.hasTag('extinct'), isTrue);
  });
}
