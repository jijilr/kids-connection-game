import 'dimension.dart';

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
  ///
  /// A thing that fits several values of a field lists them all, and one that experts
  /// debate is marked "depends". Such a thing has no single answer: its answer here is
  /// [Dimension.inBetween]. Until four of them can be a group of their own on a set
  /// sorted by that field, it joins no group there, as before.
  String? valueFor(String fieldId) {
    final value = fields[fieldId];
    if (value == null) return null;
    if (value == 'depends' || (value is List && value.length > 1)) return Dimension.inBetween;
    return value is List ? (value.isEmpty ? null : '${value.first}') : value.toString();
  }

  /// The answers this thing lies between, for a field it has no single answer to. Empty
  /// when it names none: the people who know simply do not agree.
  List<String> sidesOf(String fieldId) {
    final value = fields[fieldId];
    return value is List && value.length > 1 ? [for (final v in value) '$v'] : const [];
  }

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
