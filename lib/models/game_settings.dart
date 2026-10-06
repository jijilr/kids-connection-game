/// How the game starts. Kept apart from the data: no thing or field knows it is the
/// start, so this can change without touching either. Loaded from `settings.json`.
class GameSettings {
  /// The field the first board sorts by.
  final String startField;

  /// Breadcrumb label for the first board.
  final String startLabel;

  /// Values to keep on a board whenever its field has more than four to choose from,
  /// e.g. keep "dinosaur" among the kinds of animal.
  final Map<String, List<String>> keepInPlay;

  const GameSettings({
    required this.startField,
    required this.startLabel,
    this.keepInPlay = const {},
  });

  factory GameSettings.fromJson(Map<String, dynamic> json) {
    final start = json['start'] as Map<String, dynamic>;
    final keep = (json['keep_in_play'] as Map<String, dynamic>?) ?? const {};
    return GameSettings(
      startField: start['field'] as String,
      startLabel: start['label'] as String,
      keepInPlay: keep.map((k, v) => MapEntry(k, (v as List).cast<String>())),
    );
  }
}
