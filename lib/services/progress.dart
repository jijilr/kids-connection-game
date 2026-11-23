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
  Progress({
    Map<String, BoardProgress>? boards,
    Map<String, BoardProgress>? orders,
    Map<String, GroupProgress>? groups,
    this.lastBoard,
    this.updated,
  })  : boards = boards ?? {},
        orders = orders ?? {},
        groups = groups ?? {};

  /// Board id -> what happened there. A board's id is the path that leads to it:
  /// `seed`, `animal`, `animal/dinosaur`. The job names circles the same way.
  final Map<String, BoardProgress> boards;

  /// Boards he solved from which there was nowhere deeper to go: an order for more
  /// content there. For each, how often it happened (kept in `solved`) and when last.
  /// The job that prepares the next level reads these and fetches one group for each.
  final Map<String, BoardProgress> orders;
  /// Group id -> how he has found that group. A group's id is the id of the board inside
  /// it (`animal`, `animal/dinosaur`), so the game and the job can both tell where he has
  /// shown mastery and where he has not.
  final Map<String, GroupProgress> groups;

  String? lastBoard;
  DateTime? updated;

  /// 2 since 23 Nov 2026: the groups he has found, and how cleanly.
  static const version = 2;

  /// He found [group] on a board. Clean means no wrong guess on that board took in any of
  /// its things and no clue was asked for it: a find that shows he knows it, not luck.
  void found(String group, DateTime now, {required bool clean}) {
    final g = groups.putIfAbsent(group, GroupProgress.new)
      ..found += 1
      ..last = now;
    if (clean) {
      g.clean += 1;
      final day = _day(now);
      if (!g.cleanDays.contains(day)) {
        g.cleanDays.add(day);
        if (g.cleanDays.length > GroupProgress.daysKept) g.cleanDays.removeAt(0);
      }
    }
    updated = now;
  }

  /// Whether he has shown mastery of [group]: found cleanly on at least [days] different
  /// days. One lucky find proves nothing; the same find on another day does.
  bool mastered(String group, {int days = 2}) => (groups[group]?.cleanDays.length ?? 0) >= days;

  static String _day(DateTime t) {
    final d = t.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

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

  /// He solved [board] and no group of it could be dug into: more is wanted there.
  void order(String board, DateTime now) {
    orders.putIfAbsent(board, BoardProgress.new)
      ..solved += 1
      ..last = now;
    updated = now;
  }

  /// How often he has opened [board].
  int timesOpened(String board) => boards[board]?.opened ?? 0;

  /// When he last opened [board], or null if never.
  DateTime? lastSeen(String board) => boards[board]?.last;

  /// Boards he has opened at least once: where he has been.
  List<String> get played =>
      [for (final e in boards.entries) if (e.value.opened > 0) e.key];

  Map<String, dynamic> toJson() => {
        'what': 'Saved progress of the Connections game: boards opened and solved on one device.',
        'version': version,
        'updated': updated?.toUtc().toIso8601String(),
        'last_board': lastBoard,
        'boards': {for (final e in boards.entries) e.key: e.value.toJson()},
        'orders': {for (final e in orders.entries) e.key: e.value.toJson()},
        'groups': {for (final e in groups.entries) e.key: e.value.toJson()},
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
    final orders = <String, BoardProgress>{};
    final asked = json['orders'];
    if (asked is Map) {
      asked.forEach((key, value) {
        if (value is Map) orders['$key'] = BoardProgress.fromJson(Map<String, dynamic>.from(value));
      });
    }
    final groups = <String, GroupProgress>{};
    final found = json['groups'];
    if (found is Map) {
      found.forEach((key, value) {
        if (value is Map) groups['$key'] = GroupProgress.fromJson(Map<String, dynamic>.from(value));
      });
    }
    return Progress(
      boards: boards,
      orders: orders,
      groups: groups,
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

/// How he has found one group: how often, how often cleanly, and on which days cleanly.
class GroupProgress {
  GroupProgress({this.found = 0, this.clean = 0, List<String>? cleanDays, this.last})
      : cleanDays = cleanDays ?? [];
  int found;
  int clean;

  /// The days (yyyy-mm-dd, on the device's clock) he found it cleanly; the latest few.
  final List<String> cleanDays;
  DateTime? last;

  static const daysKept = 5;

  Map<String, dynamic> toJson() => {
        'found': found,
        'clean': clean,
        'clean_days': cleanDays,
        'last': last?.toUtc().toIso8601String(),
      };

  factory GroupProgress.fromJson(Map<String, dynamic> json) => GroupProgress(
        found: (json['found'] as num?)?.toInt() ?? 0,
        clean: (json['clean'] as num?)?.toInt() ?? 0,
        cleanDays: [
          for (final d in (json['clean_days'] is List ? json['clean_days'] as List : const []))
            if (d is String) d
        ],
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
