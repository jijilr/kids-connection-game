// Replaces the broken stock counter test. Engine tests live in engine_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:connections_game/models/entity.dart';

void main() {
  test('Entity fields: valueFor / isIn / label', () {
    const e = Entity(
      id: 'tyrannosaurus_rex',
      name: 'Tyrannosaurus rex',
      shownAs: 'T. rex',
      fields: {'kind_of_animal': 'dinosaur', 'extinct': true},
    );
    expect(e.label, 'T. rex');
    expect(e.valueFor('kind_of_animal'), 'dinosaur');
    expect(e.valueFor('extinct'), 'true');
    expect(e.valueFor('kind_of_dinosaur'), isNull); // a field that does not apply is absent
    expect(e.isIn('kind_of_animal', 'dinosaur'), isTrue);
    expect(e.isIn('kind_of_animal', 'reptile'), isFalse);
  });
}
