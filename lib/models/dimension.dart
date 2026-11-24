/// One field of the dictionary — a *way of grouping* things: by kind, by whether
/// it is extinct. [values] maps each allowed value to its kid-facing group label.
class Dimension {
  /// The key of the group "in between" (the owner's ruling of 24 Nov 2026: "things resist
  /// binary classification"). Some things have no single answer to a question: they fit
  /// two of its answers at once, or the people who know do not agree. They are not left
  /// out and not forced into one answer: once there are four of them they are a group of
  /// their own on a set sorted by that question. No thing stores this key. A thing is in
  /// between when it lists several answers, or is marked "depends" (see Entity.valueFor).
  static const inBetween = 'in_between';

  final String id;
  final String question; // the wording a child sees and hears, e.g. "What kind of animal is it?"

  /// Every group this field can form: allowed value -> group label. For a field that
  /// sorts sets this includes [inBetween].
  final Map<String, String> values;

  /// False for fields that are stored but never sort a board (the `_academic` ones).
  final bool sortsBoards;

  const Dimension({
    required this.id,
    required this.question,
    required this.values,
    this.sortsBoards = true,
  });

  /// The real answers to the question: every value but [inBetween].
  Iterable<String> get kinds => values.keys.where((v) => v != inBetween);

  /// How many distinct answers this field has. A 4×4 board needs >= 4.
  int get arity => kinds.length;

  String label(String value) => values[value] ?? value;

  factory Dimension.fromJson(String id, Map<String, dynamic> json) {
    final values =
        Map<String, String>.from((json['values'] as Map?) ?? const <String, String>{});
    final sorts = json['sorts_boards'] as bool? ?? true;
    if (sorts && values.length >= 4 && !values.containsKey(inBetween)) {
      final own = json['in_between'];
      values[inBetween] = own is Map && own['label'] is String ? own['label'] as String : 'In between';
    }
    return Dimension(
      id: id,
      question: json['wording'] as String? ?? '',
      values: values,
      sortsBoards: sorts,
    );
  }
}

/// The dictionary: every field a thing may carry, and the only values each may
/// take. Loaded once from `dictionary.json`.
class DimensionRegistry {
  final Map<String, Dimension> _byId;

  /// Goes up by one each time the dictionary gains a field.
  final int version;

  /// The places below which nothing lies: the end of a branch (place -> why). The job
  /// writes these when it finds that the world holds too few such things to sort them
  /// further. An end is a place, named by all the circles it lies in: since a question may
  /// be asked across several places, one answer to it no longer names one place (the pets
  /// among the mammals are not the pets among the birds).
  final Map<String, String> ends;

  const DimensionRegistry(this._byId, {this.version = 1, this.ends = const {}});

  Dimension? byId(String id) => _byId[id];
  Iterable<Dimension> get all => _byId.values;

  /// Where a field stands in the dictionary. A place is named by the circles it lies in,
  /// in this order, whatever the road that led to it (see BoardAssembler.canon).
  int positionOf(String id) {
    int i = 0;
    for (final key in _byId.keys) {
      if (key == id) return i;
      i++;
    }
    return i;
  }

  /// Fields that could fill a 4-group board (>= 4 values, and allowed to sort one).
  Iterable<Dimension> get boardable =>
      _byId.values.where((d) => d.sortsBoards && d.arity >= 4);

  factory DimensionRegistry.fromJson(Map<String, dynamic> json) {
    final map = <String, Dimension>{};
    (json['fields'] as Map<String, dynamic>).forEach((id, v) {
      // A field merged into another asked the very same question inside a smaller circle
      // (tools/job/cross.py). The game does not see it: its answers live on under the
      // field it was merged into, and it must never count as a second way to sort a set.
      if ((v as Map<String, dynamic>)['merged_into'] != null) return;
      map[id] = Dimension.fromJson(id, v);
    });
    final ends = json['ends'];
    return DimensionRegistry(map, version: json['version'] as int? ?? 1, ends: {
      if (ends is Map)
        for (final e in ends.entries)
          '${e.key}': e.value is Map ? '${(e.value as Map)['why'] ?? ''}' : '${e.value}'
    });
  }
}
