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
    List<String>? lines,
    Set<String>? webSeen,
    this.lastBoard,
    this.updated,
  })  : boards = boards ?? {},
        orders = orders ?? {},
        groups = groups ?? {},
        lines = lines ?? [],
        webSeen = webSeen ?? {};

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

  /// The lines to follow next, best first: the groups he did well whose own set he has
  /// not played yet. A group's id is the id of the set inside it. The game shows the
  /// first of these that is ready; the helper on the owner's PC prepares the ones that
  /// are not, a few ahead of him (the owner's design of 24 Nov 2026).
  final List<String> lines;

  /// The knots of his web that he has been shown already. What is not in here is new,
  /// and lights up the next time the web opens ("your web grew").
  final Set<String> webSeen;

  /// 3 since 24 Nov 2026: the lines to follow. (2 recorded the groups found.)
  static const version = 3;

  /// He found [group] on a set. Clean means no wrong guess took in any of its things and
  /// no clue was asked. [wrong] is how many wrong guesses took in one of its things, and
  /// [things] the four it was shown with: a kind that comes up again is then shown with
  /// other things where it can be.
  void found(String group, DateTime now,
      {required bool clean, int wrong = 0, List<String> things = const []}) {
    final g = groups.putIfAbsent(group, GroupProgress.new)
      ..found += 1
      ..wrong += wrong
      ..last = now;
    if (clean) g.clean += 1;
    if (things.isNotEmpty) g.things = [...things];
    updated = now;
  }

  /// He finished the set [board], whose groups were [all]. [didWell] are the ones he did
  /// well, best first. The groups he did well go to the front, so the best line of the
  /// newest set is followed first; a group he did not do well this time is no longer a
  /// line to follow.
  ///
  /// A set shows four kinds, and its place may hold more (the owner's ruling of 24 Nov
  /// 2026). [unfinished] are the sets he has played in which a kind is still untested.
  /// Such a set is not used up: if it is this one, it comes first of all, so that its
  /// kinds are covered in the fewest rounds before any of them is gone into ("get it
  /// over with"); only then is it known which of them he does best. Another such set, in
  /// which a kind has appeared since he played it, follows the groups he has just done
  /// well.
  void finished(String board,
      {required List<String> all, required List<String> didWell, List<String> unfinished = const []}) {
    lines.removeWhere((id) => id == board || all.contains(id));
    lines.insertAll(0, didWell);
    lines.insertAll(didWell.length, [
      for (final id in unfinished)
        if (id != board && !lines.contains(id)) id
    ]);
    if (unfinished.contains(board)) lines.insert(0, board);
  }

  /// Lines that can never be made into a set (the helper says so) are let go.
  void drop(Iterable<String> dead) => lines.removeWhere(dead.contains);

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
        'lines': lines,
        'web_seen': webSeen.toList()..sort(),
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
      lines: [
        for (final id in (json['lines'] is List ? json['lines'] as List : const []))
          if (id is String) id
      ],
      webSeen: {
        for (final id in (json['web_seen'] is List ? json['web_seen'] as List : const []))
          if (id is String) id
      },
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

/// How he has found one group: how often, how often cleanly, how many wrong guesses took
/// in its things, and the things it was last shown with.
class GroupProgress {
  GroupProgress({this.found = 0, this.clean = 0, this.wrong = 0, List<String>? things, this.last})
      : things = things ?? [];
  int found;
  int clean;
  int wrong;
  List<String> things;
  DateTime? last;

  /// How well he does this kind, from 0 to 1: the share of times he found it cleanly, and
  /// between kinds alike in that, the one with fewer wrong guesses is the better.
  double get howWell =>
      found == 0 ? 0 : clean / found - (wrong / found).clamp(0, 9) / 100;

  Map<String, dynamic> toJson() => {
        'found': found,
        'clean': clean,
        'wrong': wrong,
        'things': things,
        'last': last?.toUtc().toIso8601String(),
      };

  factory GroupProgress.fromJson(Map<String, dynamic> json) => GroupProgress(
        found: json['found'] is num ? (json['found'] as num).toInt() : 0,
        clean: json['clean'] is num ? (json['clean'] as num).toInt() : 0,
        wrong: json['wrong'] is num ? (json['wrong'] as num).toInt() : 0,
        things: [
          for (final id in (json['things'] is List ? json['things'] as List : const []))
            if (id is String) id
        ],
        last: DateTime.tryParse('${json['last'] ?? ''}'),
      );
}

/// Where progress is kept between visits.
abstract class ProgressStore {
  Future<Progress> load();
  Future<void> save(Progress progress);

  /// A switch kept on this device, such as whether the app chooses the way by itself.
  Future<bool> loadFlag(String name, {required bool otherwise});
  Future<void> saveFlag(String name, bool value);
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

  final _flags = <String, bool>{};
  @override
  Future<bool> loadFlag(String name, {required bool otherwise}) async => _flags[name] ?? otherwise;
  @override
  Future<void> saveFlag(String name, bool value) async => _flags[name] = value;
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

  @override
  Future<bool> loadFlag(String name, {required bool otherwise}) async {
    try {
      return (await SharedPreferences.getInstance()).getBool('flag_$name') ?? otherwise;
    } catch (_) {
      return otherwise;
    }
  }

  @override
  Future<void> saveFlag(String name, bool value) async {
    try {
      await (await SharedPreferences.getInstance()).setBool('flag_$name', value);
    } catch (_) {
      // as with progress: the game goes on
    }
  }
}
