/// One field of the dictionary — a *way of grouping* things: by kind, by whether
/// it is extinct. [values] maps each allowed value to its kid-facing group label.
class Dimension {
  final String id;
  final String question; // the wording a child sees and hears, e.g. "What kind of animal is it?"
  final Map<String, String> values; // allowed value -> group label

  /// False for fields that are stored but never sort a board (the `_academic` ones).
  final bool sortsBoards;

  const Dimension({
    required this.id,
    required this.question,
    required this.values,
    this.sortsBoards = true,
  });

  /// How many distinct groups this field can form. A 4×4 board needs >= 4.
  int get arity => values.length;

  String label(String value) => values[value] ?? value;

  factory Dimension.fromJson(String id, Map<String, dynamic> json) => Dimension(
        id: id,
        question: json['wording'] as String? ?? '',
        values: Map<String, String>.from(
            (json['values'] as Map?) ?? const <String, String>{}),
        sortsBoards: json['sorts_boards'] as bool? ?? true,
      );
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
