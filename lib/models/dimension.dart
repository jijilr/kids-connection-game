/// A *way of grouping* entities — by category, by diet, by era (PRD Part II).
/// [values] maps a tag-value to its kid-facing display label.
class Dimension {
  final String id;
  final String type; // "intrinsic" (readable off the thing) | "contextual" (needs scene)
  final String question; // announced-mode prompt, e.g. "What does it eat?"
  final Map<String, String> values; // tag-value -> display label

  const Dimension({
    required this.id,
    required this.type,
    required this.question,
    required this.values,
  });

  /// How many distinct groups this dimension can form. A 4×4 board needs >= 4.
  int get arity => values.length;

  String label(String value) => values[value] ?? value;

  factory Dimension.fromJson(String id, Map<String, dynamic> json) => Dimension(
        id: id,
        type: json['type'] as String? ?? 'intrinsic',
        question: json['question'] as String? ?? '',
        values: Map<String, String>.from(
            (json['values'] as Map?) ?? const <String, String>{}),
      );
}

/// The canonical dimension registry — so lazily-added tags always compose to the
/// same dimensions (PRD VI.0). Loaded once from `dimensions.json`.
class DimensionRegistry {
  final Map<String, Dimension> _byId;
  const DimensionRegistry(this._byId);

  Dimension? byId(String id) => _byId[id];
  Iterable<Dimension> get all => _byId.values;

  /// Dimensions that can fill a 4-group board (>= 4 values).
  Iterable<Dimension> get boardable => _byId.values.where((d) => d.arity >= 4);

  /// Which dimension does a tag-value belong to? e.g. "carnivore" -> diet.
  Dimension? dimensionForValue(String value) {
    for (final d in _byId.values) {
      if (d.values.containsKey(value)) return d;
    }
    return null;
  }

  factory DimensionRegistry.fromJson(Map<String, dynamic> json) {
    final map = <String, Dimension>{};
    json.forEach(
        (id, v) => map[id] = Dimension.fromJson(id, v as Map<String, dynamic>));
    return DimensionRegistry(map);
  }
}
