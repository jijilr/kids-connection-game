import 'package:flutter/foundation.dart';
import '../models/entity.dart';
import '../models/dimension.dart';
import '../services/board_assembler.dart';
import '../services/content_repository.dart';

/// One stop on the traversal path: the filter that got us here + the dimension
/// this board sorts by + a breadcrumb label.
class _Level {
  final List<PathFilter> filter;
  final Dimension dim;
  final String label;
  _Level(this.filter, this.dim, this.label);
}

/// The text-engine game state (PRD III / BUILD_PLAN P1): a 4×4 board assembled
/// fresh from the graph, plus the filter-stack traversal (descend / back).
class EngineProvider extends ChangeNotifier {
  final ContentRepository _repo = ContentRepository();
  bool isLoading = true;

  final List<_Level> _stack = [];
  Board? board;
  final List<Entity> selected = [];
  final List<BoardGroup> solved = [];
  int mistakes = 0;
  static const int maxMistakes = 4;
  String message = '';
  bool atFloor = false;

  DimensionRegistry get registry => _repo.registry;
  bool get atRoot => _stack.length <= 1;
  bool get boardComplete =>
      board != null && solved.length == board!.groups.length;
  List<String> get pathLabels => _stack.map((l) => l.label).toList();
  List<Entity> get openTiles =>
      board == null ? const [] : board!.tiles.where((e) => !isSolved(e)).toList();

  Future<void> init() async {
    await _repo.load(domain: 'animals');
    _stack.add(_Level(const [], registry.byId('category')!, 'Animals'));
    _open();
    isLoading = false;
    notifyListeners();
  }

  void _open() {
    final lvl = _stack.last;
    board = _repo.assembler.assemble(filter: lvl.filter, dimension: lvl.dim);
    atFloor = board == null;
    selected.clear();
    solved.clear();
    mistakes = 0;
    message = atFloor
        ? 'This branch is as deep as it goes for now.'
        : 'Sort them by: ${lvl.dim.question}';
    notifyListeners();
  }

  /// Reshuffle the current level into a fresh board.
  void newBoard() {
    if (!atFloor) _open();
  }

  bool isSolved(Entity e) =>
      solved.any((g) => g.items.any((x) => x.id == e.id));

  void toggle(Entity e) {
    if (boardComplete || isSolved(e)) return;
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

  void submit() {
    if (selected.length != 4 || board == null) return;
    final selIds = selected.map((e) => e.id).toSet();
    BoardGroup? hit;
    for (final g in board!.groups) {
      if (solved.contains(g)) continue;
      final gIds = g.items.map((e) => e.id).toSet();
      if (gIds.length == 4 && gIds.containsAll(selIds)) {
        hit = g;
        break;
      }
    }
    if (hit != null) {
      solved.add(hit);
      selected.clear();
      message = boardComplete
          ? 'Solved! Tap a group to dig deeper.'
          : 'Nice — ${hit.label}!';
    } else {
      mistakes++;
      final near = board!.groups.any((g) =>
          !solved.contains(g) &&
          g.items.where((e) => selIds.contains(e.id)).length == 3);
      message = near ? 'So close — one away!' : 'Not a group — try again.';
      selected.clear();
    }
    notifyListeners();
  }

  /// Descend into a solved group: push its filter, open the next boardable level.
  void descendInto(BoardGroup g) {
    if (!boardComplete) return;
    final newFilter = <PathFilter>[..._stack.last.filter, (g.dimId, g.value)];
    final dims = _repo.assembler.boardableDimensions(newFilter);
    final dim = dims.isNotEmpty ? dims.first : _stack.last.dim; // dummy -> floor
    _stack.add(_Level(newFilter, dim, g.label));
    _open();
  }

  void back() {
    if (_stack.length <= 1) return;
    _stack.removeLast();
    _open();
  }

  /// Other lenses that re-sort the *same* animals at this node (the "wider" move).
  List<Dimension> get regroupOptions => board == null
      ? const []
      : _repo.assembler.regroupDimensions(_stack.last.filter, _stack.last.dim.id);

  /// Regroup: same node (same filter + breadcrumb), a different sorting dimension.
  void regroupBy(Dimension d) {
    final lvl = _stack.last;
    _stack[_stack.length - 1] = _Level(lvl.filter, d, lvl.label);
    _open();
  }
}
