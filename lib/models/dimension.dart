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

  /// The answers below which nothing lies: the end of a branch (value -> why). The job
  /// writes these when it finds that the world holds too few such things to sort further.
  final Map<String, String> ends;

  const Dimension({
    required this.id,
    required this.question,
    required this.values,
    this.sortsBoards = true,
    this.ends = const {},
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
    final ends = json['ends'];
    return Dimension(
      id: id,
      question: json['wording'] as String? ?? '',
      values: values,
      sortsBoards: sorts,
      ends: {
        if (ends is Map)
          for (final e in ends.entries) '${e.key}': e.value is Map ? '${(e.value as Map)['why'] ?? ''}' : '${e.value}'
      },
    );
  }
}

/// The dictionary: every field a thing may carry, and the only values each may
/// take. Loaded once from `dictionary.json`.
class DimensionRegistry {
  final Map<String, Dimension> _byId;

  /// Goes up by one each time the dictionary gains a field.
  final int version;

  const DimensionRegistry(this._byId, {this.version = 1});

  Dimension? byId(String id) => _byId[id];
  Iterable<Dimension> get all => _byId.values;

  /// Fields that could fill a 4-group board (>= 4 values, and allowed to sort one).
  Iterable<Dimension> get boardable =>
      _byId.values.where((d) => d.sortsBoards && d.arity >= 4);

  factory DimensionRegistry.fromJson(Map<String, dynamic> json) {
    final map = <String, Dimension>{};
    (json['fields'] as Map<String, dynamic>).forEach(
        (id, v) => map[id] = Dimension.fromJson(id, v as Map<String, dynamic>));
    return DimensionRegistry(map, version: json['version'] as int? ?? 1);
  }
}
