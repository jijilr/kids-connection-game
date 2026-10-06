import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'board_assembler.dart';

/// What the child has played, kept on this device and nowhere else.
///
/// It records boards, not the child: for each board, how often it was opened and
/// solved, and when last. No name, no account, nothing about who is playing. The
/// "prepare the next level" job reads a saved copy of it to know where he is, so it
/// can prepare one step ahead of him (the owner's ruling of 7 Oct 2026).
class Progress {
  Progress({Map<String, BoardProgress>? boards, this.lastBoard, this.updated})
      : boards = boards ?? {};

  /// Board id -> what happened there. A board's id is the path that leads to it:
  /// `seed`, `animal`, `animal/dinosaur`. The job names circles the same way.
  final Map<String, BoardProgress> boards;
  String? lastBoard;
  DateTime? updated;

  static const version = 1;

  /// The id of the board reached by [filter]: the values chosen on the way, in order.
  static String boardId(List<PathFilter> filter) =>
      filter.isEmpty ? 'seed' : filter.map((step) => step.$2).join('/');

  void opened(String board, DateTime now) {
    boards.putIfAbsent(board, BoardProgress.new)
      ..opened += 1
      ..last = now;
    lastBoard = board;
    updated = now;
  }

  void solved(String board, DateTime now) {
    boards.putIfAbsent(board, BoardProgress.new)
      ..solved += 1
      ..last = now;
    lastBoard = board;
    updated = now;
  }

  /// Boards he has opened at least once: where he has been.
  List<String> get played =>
      [for (final e in boards.entries) if (e.value.opened > 0) e.key];

  Map<String, dynamic> toJson() => {
        'what': 'Saved progress of the Connections game: boards opened and solved on one device.',
        'version': version,
        'updated': updated?.toUtc().toIso8601String(),
        'last_board': lastBoard,
        'boards': {for (final e in boards.entries) e.key: e.value.toJson()},
      };

  /// The text of the file a grown-up saves for the job.
  String toFileText() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory Progress.fromJson(Map<String, dynamic> json) {
    final boards = <String, BoardProgress>{};
    final saved = json['boards'];
    if (saved is Map) {
      saved.forEach((key, value) {
        if (value is Map) boards['$key'] = BoardProgress.fromJson(Map<String, dynamic>.from(value));
      });
    }
    return Progress(
      boards: boards,
      lastBoard: json['last_board'] as String?,
      updated: DateTime.tryParse('${json['updated'] ?? ''}'),
    );
  }
}

class BoardProgress {
  BoardProgress({this.opened = 0, this.solved = 0, this.last});
  int opened;
  int solved;
  DateTime? last;

  Map<String, dynamic> toJson() =>
      {'opened': opened, 'solved': solved, 'last': last?.toUtc().toIso8601String()};

  factory BoardProgress.fromJson(Map<String, dynamic> json) => BoardProgress(
        opened: (json['opened'] as num?)?.toInt() ?? 0,
        solved: (json['solved'] as num?)?.toInt() ?? 0,
        last: DateTime.tryParse('${json['last'] ?? ''}'),
      );
}

/// Where progress is kept between visits.
abstract class ProgressStore {
  Future<Progress> load();
  Future<void> save(Progress progress);
}

/// Kept in memory only: for tests, and the fallback when the device refuses storage.
class MemoryProgressStore implements ProgressStore {
  String? _text;
  @override
  Future<Progress> load() async => _text == null
      ? Progress()
      : Progress.fromJson(jsonDecode(_text!) as Map<String, dynamic>);
  @override
  Future<void> save(Progress progress) async => _text = jsonEncode(progress.toJson());
}

/// Kept on the device: the browser's own storage on the web, the app's preferences
/// elsewhere. Saving must never break the game, so every failure is swallowed.
class DeviceProgressStore implements ProgressStore {
  static const _key = 'progress_v1';

  @override
  Future<Progress> load() async {
    try {
      final text = (await SharedPreferences.getInstance()).getString(_key);
      if (text == null) return Progress();
      return Progress.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
      return Progress();
    }
  }

  @override
  Future<void> save(Progress progress) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(progress.toJson()));
    } catch (_) {
      // nothing to do: the game goes on, and the next save tries again
    }
  }
}
