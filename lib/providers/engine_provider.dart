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
    Board? b;
    final size = registry.byId('size');
    // Root/category boards are built as a category×size grid so the SAME 16 can
    // be regrouped by size (the "same animals, new lens" magic).
    if (lvl.dim.id == 'category' && size != null) {
      b = _repo.assembler.assembleGrid(filter: lvl.filter, rowDim: lvl.dim, colDim: size);
    }
    b ??= _repo.assembler.assemble(filter: lvl.filter, dimension: lvl.dim);
    board = b;
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

  /// Lenses that re-sort the *exact same tiles* a different way (the "wider" move).
  List<Dimension> get regroupOptions {
    final b = board;
    if (b == null) return const [];
    return b.lenses.where((d) => d.id != b.dimension.id).toList();
  }

  /// Regroup: keep the SAME 16 tiles, re-partition them by a new lens. This is the
  /// "watch Tiger jump from Mammals to Big" moment — same animals, new grouping.
  void regroupBy(Dimension d) {
    final b = board;
    if (b == null) return;
    final groups = _repo.assembler.partitionBy(b.tiles, d);
    if (groups == null) return;
    board = Board(
      dimension: d,
      groups: groups,
      tiles: b.tiles,
      filter: b.filter,
      lenses: b.lenses,
    );
    final lvl = _stack.last;
    _stack[_stack.length - 1] = _Level(lvl.filter, d, lvl.label);
    selected.clear();
    solved.clear();
    mistakes = 0;
    message = 'Same animals — now sorted by ${d.question.toLowerCase()}';
    notifyListeners();
  }
}
