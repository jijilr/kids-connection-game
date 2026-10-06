import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/entity.dart';
import '../models/dimension.dart';
import '../services/board_assembler.dart';
import '../services/content_repository.dart';
import '../services/media.dart';

/// One stop on the traversal path: the filter that got us here + the rule this
/// board sorts by + a breadcrumb label.
class _Level {
  final List<PathFilter> filter;
  final Dimension dim;
  final String label;
  _Level(this.filter, this.dim, this.label);
}

/// What happened on Submit — the screen turns this into sounds.
enum SubmitResult { notReady, correct, roundDone, wrong, oneAway }

/// Game state for the text/picture engine: a 4×4 board assembled fresh from the
/// graph (one named rule per board) and the filter-stack traversal (dig deeper / back).
class EngineProvider extends ChangeNotifier {
  EngineProvider({ContentRepository? repo, Random? random})
      : _repo = repo ?? ContentRepository(),
        _random = random ?? Random();

  final ContentRepository _repo;
  final Random _random;
  bool isLoading = true;

  final List<_Level> _stack = [];

  Board? board;
  final List<BoardGroup> solved = [];
  final List<Entity> selected = [];
  List<Entity> _order = [];
  int mistakes = 0;
  bool atFloor = false;
  bool _emojiFirst = false;
  String message = '';

  DimensionRegistry get registry => _repo.registry;
  bool get atRoot => _stack.length <= 1;
  List<String> get pathLabels => _stack.map((l) => l.label).toList();

  // ---------------------------------------------------------------- derived state

  /// All 4 groups found — nothing left to do on this board.
  bool get boardFinished => board != null && solved.length == 4;

  /// Tiles still in play, in display order.
  List<Entity> get openTiles => _order.where((e) => !isSolved(e)).toList();

  /// The instruction shown (and read aloud) at the top.
  String get prompt => board?.dimension.question ?? '';

  int get stars => mistakes == 0 ? 3 : (mistakes <= 2 ? 2 : 1);

  /// Picture for a tile, in this board's single most uniform style (photos or emoji),
  /// so a tile's *look* never gives its group away.
  EntityMedia tileMedia(Entity e) {
    final m = _repo.media.forEntity(e);
    if (_emojiFirst && m.emoji != null) return EntityMedia(emoji: m.emoji, audio: m.audio);
    if (m.image != null) return EntityMedia(image: m.image, audio: m.audio);
    return m;
  }

  bool isSelected(Entity e) => selected.any((x) => x.id == e.id);
  bool isSolved(Entity e) => solved.any((g) => g.items.any((x) => x.id == e.id));

  /// Only offer "dig deeper" where there really is a deeper 4×4 to play.
  bool canDescend(BoardGroup g) {
    if (!boardFinished) return false;
    return _repo.assembler.boardableDimensions(_childFilter(g)).isNotEmpty;
  }

  bool get anyDescendable => solved.any(canDescend);

  // ---------------------------------------------------------------------- actions

  Future<void> init() async {
    await _repo.load();
    final start = _repo.settings;
    _stack
      ..clear()
      ..add(_Level(const [], registry.byId(start.startField)!, start.startLabel));
    _open();
    isLoading = false;
    notifyListeners();
  }

  void _open() {
    final lvl = _stack.last;
    final b = _repo.assembler.assemble(
        filter: lvl.filter,
        dimension: lvl.dim,
        preferValues: _repo.settings.keepInPlay[lvl.dim.id] ?? const []);

    board = b;
    atFloor = b == null;
    solved.clear();
    selected.clear();
    mistakes = 0;
    _order = b == null ? [] : [...b.tiles];
    _emojiFirst = b != null && _uniformity(b, emojiFirst: true) > _uniformity(b, emojiFirst: false);
    message = '';
    notifyListeners();
  }

  /// Size of the largest same-style group of tiles (photo / emoji / text).
  int _uniformity(Board b, {required bool emojiFirst}) {
    final counts = <String, int>{};
    for (final t in b.tiles) {
      final m = _repo.media.forEntity(t);
      final kind = emojiFirst
          ? (m.emoji != null ? 'emoji' : m.image != null ? 'photo' : 'text')
          : (m.image != null ? 'photo' : m.emoji != null ? 'emoji' : 'text');
      counts[kind] = (counts[kind] ?? 0) + 1;
    }
    return counts.values.fold(0, max);
  }

  /// A fresh board at this level.
  void newBoard() {
    if (!atFloor) _open();
  }

  void toggle(Entity e) {
    if (boardFinished || isSolved(e)) return;
    final i = selected.indexWhere((x) => x.id == e.id);
    if (i >= 0) {
      selected.removeAt(i);
    } else if (selected.length < 4) {
      selected.add(e);
    }
    notifyListeners();
  }

  void deselectAll() {
    selected.clear();
    notifyListeners();
  }

  void shuffleTiles() {
    _order.shuffle(_random);
    notifyListeners();
  }

  SubmitResult submit() {
    final b = board;
    if (b == null || selected.length != 4 || boardFinished) return SubmitResult.notReady;
    final ids = selected.map((e) => e.id).toSet();

    for (final g in b.groups) {
      if (_isSolvedGroup(g) || !_same(g, ids)) continue;
      solved.add(g);
      selected.clear();
      if (boardFinished) {
        message = 'Solved!';
        notifyListeners();
        return SubmitResult.roundDone;
      }
      message = 'Yes! ${g.label}';
      notifyListeners();
      return SubmitResult.correct;
    }

    mistakes++;
    final near = b.groups.any((g) =>
        !_isSolvedGroup(g) && g.items.where((e) => ids.contains(e.id)).length == 3);
    message = near ? 'So close — one away!' : 'Not quite — try another group.';
    selected.clear();
    notifyListeners();
    return near ? SubmitResult.oneAway : SubmitResult.wrong;
  }

  void descendInto(BoardGroup g) {
    if (!canDescend(g)) return;
    final f = _childFilter(g);
    final dims = _repo.assembler.boardableDimensions(f);
    _stack.add(_Level(f, dims.first, g.label));
    _open();
  }

  void back() {
    if (_stack.length <= 1) return;
    _stack.removeLast();
    _open();
  }

  // --------------------------------------------------------------------- helpers

  List<PathFilter> _childFilter(BoardGroup g) =>
      <PathFilter>[..._stack.last.filter, (g.dimId, g.value)];

  bool _isSolvedGroup(BoardGroup g) =>
      solved.any((s) => s.dimId == g.dimId && s.value == g.value);

  bool _same(BoardGroup g, Set<String> ids) =>
      g.items.length == 4 && g.items.every((e) => ids.contains(e.id));
}
