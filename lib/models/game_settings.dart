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

  /// Values kept off every board for now, e.g. a kind with too few familiar things.
  final Map<String, List<String>> holdBack;

  const GameSettings({
    required this.startField,
    required this.startLabel,
    this.keepInPlay = const {},
    this.holdBack = const {},
  });

  factory GameSettings.fromJson(Map<String, dynamic> json) {
    final start = json['start'] as Map<String, dynamic>;
    Map<String, List<String>> lists(String key) =>
        ((json[key] as Map<String, dynamic>?) ?? const {})
            .map((k, v) => MapEntry(k, (v as List).cast<String>()));
    return GameSettings(
      startField: start['field'] as String,
      startLabel: start['label'] as String,
      keepInPlay: lists('keep_in_play'),
      holdBack: lists('hold_back'),
    );
  }
}
