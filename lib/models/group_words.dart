/// Something the game shows and says: the words, and the clip that speaks them. Where
/// there is no clip the device's own voice reads the words.
class Spoken {
  final String text;
  final String? audio;
  const Spoken(this.text, [this.audio]);

  static Spoken? fromJson(Object? json) {
    if (json is! Map) return null;
    final text = '${json['text'] ?? ''}'.trim();
    return text.isEmpty ? null : Spoken(text, json['audio'] as String?);
  }
}

/// The words of one group: a ladder of clues, each more helpful than the last, and the
/// explanation said when the child has found the group. They are written for the group
/// (a field and one of its values), not for a board, so they serve wherever it appears.
class GroupWords {
  final List<Spoken> clues;
  final Spoken? explanation;
  const GroupWords({this.clues = const [], this.explanation});
}

/// Every group's words, loaded once from `groups.json` (the game's copy; the catalogue
/// is their master record).
class GroupWordsBook {
  final Map<String, GroupWords> _byGroup;
  const GroupWordsBook(this._byGroup);
  const GroupWordsBook.empty() : _byGroup = const {};

  /// The words of the group that [value] of [field] makes, or null if none are written.
  GroupWords? of(String field, String value) => _byGroup['$field=$value'];

  int get length => _byGroup.length;

  factory GroupWordsBook.fromJson(Map<String, dynamic> json) {
    final out = <String, GroupWords>{};
    final groups = json['groups'];
    if (groups is Map) {
      groups.forEach((key, value) {
        if (value is! Map) return;
        final clues = <Spoken>[];
        final ladder = value['clues'];
        if (ladder is List) {
          for (final step in ladder) {
            final spoken = Spoken.fromJson(step);
            if (spoken != null) clues.add(spoken);
          }
        }
        out['$key'] = GroupWords(clues: clues, explanation: Spoken.fromJson(value['explanation']));
      });
    }
    return GroupWordsBook(out);
  }
}
