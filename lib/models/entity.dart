/// A single learnable thing — "T. rex", "Mango tree", "Sun".
///
/// A thing is a record of plain fields with values (`extinct: true`). Which fields
/// exist, and which values each may take, is set by the dictionary
/// ([DimensionRegistry]). A field that does not apply to a thing is simply absent.
class Entity {
  final String id;

  /// The full name kept in the data, e.g. "Tyrannosaurus rex".
  final String name;

  /// How the child says it, e.g. "T. rex". Null when it is the same as [name].
  final String? shownAs;

  final Map<String, Object?> fields;

  /// Short notes for a grown-up, keyed by the field they are about (or "general").
  final Map<String, String> notes;

  /// 0..1 — how sure we are a young child recognises it. Familiar things come first.
  final double familiar;

  const Entity({
    required this.id,
    required this.name,
    this.shownAs,
    this.fields = const {},
    this.notes = const {},
    this.familiar = 0.5,
  });

  /// The name shown on a tile and spoken aloud.
  String get label => shownAs ?? name;

  /// This thing's value for a field, spelled as the dictionary spells it ("true" /
  /// "false" for yes/no fields), or null when the field does not apply to it.
  String? valueFor(String fieldId) => fields[fieldId]?.toString();

  /// Whether this thing is in a given (field, value) group.
  bool isIn(String fieldId, String value) => valueFor(fieldId) == value;

  factory Entity.fromJson(String id, Map<String, dynamic> json) => Entity(
        id: id,
        name: json['name'] as String,
        shownAs: json['shown_as'] as String?,
        fields: Map<String, Object?>.from((json['fields'] as Map?) ?? const {}),
        notes: Map<String, String>.from((json['notes'] as Map?) ?? const {}),
        familiar: (json['familiar'] as num?)?.toDouble() ?? 0.5,
      );

  @override
  String toString() => 'Entity($id: $name)';
}
