/// A single learnable thing — "T-Rex", "Shark". The atom of the knowledge graph.
///
/// Tags are flat strings (PRD Part II). A tag that is a *value* of a dimension
/// (e.g. "carnivore" for the `diet` dimension) is looked up via the
/// [DimensionRegistry]; boolean-ish tags (e.g. "flies") are just present or absent.
class Entity {
  final String id;
  final String name;
  final String domain;
  final List<String> tags;
  final List<String> facts;

  /// 0..1 — how recognizable to a child. Drives fame / mundane-first ordering
  /// (PRD IV.3). Placeholder in the migrated seed; scored properly by DeepSeek in P2.
  final double recognizability;

  /// Where each atom came from (PRD VII.0). Seed = `human:migrated`.
  final Map<String, dynamic> provenance;

  const Entity({
    required this.id,
    required this.name,
    required this.domain,
    required this.tags,
    this.facts = const [],
    this.recognizability = 0.5,
    this.provenance = const {},
  });

  bool hasTag(String tag) => tags.contains(tag);

  /// This entity's value for a *valued* dimension, or null if it has none.
  /// Valued tags are namespaced `dimId:value` (e.g. "category:dinosaur").
  String? valueFor(String dimId) {
    final prefix = '$dimId:';
    for (final t in tags) {
      if (t.startsWith(prefix)) return t.substring(prefix.length);
    }
    return null;
  }

  /// Whether this entity is in a given (dimension, value) group.
  bool isIn(String dimId, String value) => tags.contains('$dimId:$value');

  factory Entity.fromJson(Map<String, dynamic> json) => Entity(
        id: json['id'] as String,
        name: json['name'] as String,
        domain: json['domain'] as String? ?? 'unknown',
        tags: (json['tags'] as List<dynamic>? ?? const []).cast<String>(),
        facts: (json['facts'] as List<dynamic>? ?? const []).cast<String>(),
        recognizability: (json['recognizability'] as num?)?.toDouble() ?? 0.5,
        provenance:
            (json['provenance'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      );

  @override
  String toString() => 'Entity($id: $name)';
}
