import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/entity.dart';
import '../models/dimension.dart';
import '../models/group_words.dart';
import '../services/board_assembler.dart';
import '../services/content_repository.dart';
import '../services/media.dart';
import '../services/progress.dart';

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

/// Where the button that ends a board leads: a board somewhere in the game, the path to
/// it, and why it was chosen.
class NextStep {
  final List<PathFilter> filter;
  final String label;

  /// A board inside one of the groups just found: the button says "Dig deeper".
  final bool inside;

  /// Chosen because he has shown mastery of the group that leads to it (the four in
  /// five); false when it is a set he has not mastered (the one in five, or when he has
  /// mastered nothing that leads anywhere yet).
  final bool mastered;

  const NextStep(this.filter, this.label, {required this.inside, required this.mastered});

  String get id => Progress.boardId(filter);
}

/// Game state for the text/picture engine: a 4×4 board assembled fresh from the
/// graph (one named rule per board) and the filter-stack traversal (dig deeper / back).
class EngineProvider extends ChangeNotifier {
  EngineProvider({
    ContentRepository? repo,
    Random? random,
    ProgressStore? progressStore,
    DateTime Function()? clock,
  })  : _repo = repo ?? ContentRepository(),
        _random = random ?? Random(),
        _progressStore = progressStore ?? MemoryProgressStore(),
        _now = clock ?? DateTime.now;

  final ContentRepository _repo;
  final Random _random;
  final ProgressStore _progressStore;
  final DateTime Function() _now;

  /// Which boards have been opened and solved on this device. The job that prepares
  /// the next level reads a saved copy of it to know where the child is.
  Progress progress = Progress();
  bool isLoading = true;

  final List<_Level> _stack = [];
  Set<String> _lastTiles = {};

  // Clues: a ladder for one group at a time. Asking for a clue never costs a star.
  String? _clueGroup;
  int _clueStep = -1;

  /// The clue now showing, or null.
  Spoken? clue;

  /// How many clues he has asked for on this board. Kept to see how he plays, never to mark him.
  int cluesUsed = 0;

  // On this board: the groups a wrong guess took in, and the groups a clue was asked for.
  // A group found after either is found, but not cleanly: it does not count toward mastery.
  final Set<String> _shaken = {};
  final Set<String> _clued = {};

  /// Where the button that ends this board leads, chosen once when the board is done.
  /// Null before then, and when nothing fits: the button then brings a parallel board.
  NextStep? nextStep;

  /// The explanation of the group he has just found, or null.
  Spoken? explanation;

  Board? board;
  final List<BoardGroup> solved = [];
  final List<Entity> selected = [];
  List<Entity> _order = [];
  int mistakes = 0;
  bool atFloor = false;
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

  /// Picture for a tile, in the one style this whole board is drawn in, so a tile's
  /// *look* never gives its group away.
  EntityMedia tileMedia(Entity e) => _repo.media.inStyle(e, board?.style);

  bool isSelected(Entity e) => selected.any((x) => x.id == e.id);
  bool isSolved(Entity e) => solved.any((g) => g.items.any((x) => x.id == e.id));

  /// Only offer "dig deeper" where there really is a deeper 4×4 to play — and, when the
  /// settings ask for it, only where that board can be drawn in pictures.
  bool canDescend(BoardGroup g) {
    if (!boardFinished) return false;
    final filter = _childFilter(g);
    final dims = _repo.assembler.boardableDimensions(filter);
    if (dims.isEmpty) return false;
    return !_repo.settings.boardsNeedPictures ||
        _repo.assembler.hasPictureBoard(filter, dims.first);
  }

  bool get anyDescendable => solved.any(canDescend);

  GroupWords? _wordsOf(BoardGroup g) => _repo.words.of(g.dimId, g.value);

  List<BoardGroup> get _groupsWithClues => board == null
      ? const []
      : [
          for (final g in board!.groups)
            if (!_isSolvedGroup(g) && (_wordsOf(g)?.clues.isNotEmpty ?? false)) g
        ];

  /// Whether a clue can be given now.
  bool get hasClue => !boardFinished && _groupsWithClues.isNotEmpty;

  /// The next clue: one step up the ladder of the group he is working on. The group is
  /// the one most of his chosen tiles belong to; failing that, the one the ladder is
  /// already on; failing that, the first group still to be found. A clue points at the
  /// group's idea and never names a tile. It costs no star and no mistake.
  Spoken? nextClue() {
    final open = _groupsWithClues;
    if (boardFinished || open.isEmpty) return null;
    BoardGroup? target;
    int most = 0;
    for (final g in open) {
      final chosen = g.items.where(isSelected).length;
      if (chosen > most) {
        most = chosen;
        target = g;
      }
    }
    target ??= open.where((g) => g.value == _clueGroup).firstOrNull ?? open.first;
    final ladder = _wordsOf(target)!.clues;
    _clueStep = target.value == _clueGroup ? min(_clueStep + 1, ladder.length - 1) : 0;
    _clueGroup = target.value;
    _clued.add(target.value);
    clue = ladder[_clueStep];
    cluesUsed++;
    notifyListeners();
    return clue;
  }

  /// The explanation written for [g], if any: why these belong together, and one true fact.
  Spoken? explanationOf(BoardGroup g) => _wordsOf(g)?.explanation;

  /// The solved groups that have a board inside them.
  List<BoardGroup> get diggable => solved.where(canDescend).toList();

  /// He has solved this board and no group of it can be dug into.
  bool get atADeadEnd => boardFinished && diggable.isEmpty;

  /// Whether he has shown mastery of the group that leads to the board at [id].
  bool masteredGroup(String id) => progress.mastered(id, days: _repo.settings.masteryDays);

  /// Where the button that ends a board leads. The owner's ruling of 23 Nov 2026, which
  /// replaces "lean toward the branch he has visited least": like a good recommender,
  /// four boards in five go deeper where he has shown mastery, and one in five goes to a
  /// set where he has not, so that he is not only fed what he already knows.
  ///
  /// Deeper where he has shown mastery: a board inside a group he has mastered. Inside a
  /// group just found comes first, then one he has solved least, then the one he saw
  /// longest ago.
  /// A set he has not mastered: inside a group just found comes first, then the board he
  /// has opened least, nearest the seed first. Until he has mastered anything, this is
  /// the only kind there is, and it keeps the old balance: the least visited first.
  NextStep? _chooseNext() {
    final hereFilter = _stack.last.filter;
    final here = Progress.boardId(hereFilter);
    final circles = _repo.assembler
        .circlesBelow(_stack.first.dim, needPictures: _repo.settings.boardsNeedPictures)
        .where((f) => Progress.boardId(f) != here)
        .toList();
    bool inside(List<PathFilter> f) =>
        f.length == hereFilter.length + 1 &&
        Progress.boardId(f.sublist(0, hereFilter.length)) == Progress.boardId(hereFilter) &&
        solved.any((g) => g.dimId == f.last.$1 && g.value == f.last.$2);
    final never = DateTime.fromMillisecondsSinceEpoch(0);
    // Ties go to the group found first on this board, then to the game's own order.
    int place(List<PathFilter> f) {
      final found = solved.indexWhere((g) => inside(f) && g.dimId == f.last.$1 && g.value == f.last.$2);
      return found >= 0 ? found : solved.length + circles.indexOf(f);
    }
    int compareSeen(List<PathFilter> a, List<PathFilter> b) {
      final s = (progress.lastSeen(Progress.boardId(a)) ?? never)
          .compareTo(progress.lastSeen(Progress.boardId(b)) ?? never);
      return s != 0 ? s : place(a).compareTo(place(b));
    }
    int insideFirst(List<PathFilter> a, List<PathFilter> b) => (inside(a) ? 0 : 1).compareTo(inside(b) ? 0 : 1);

    final strong = circles.where((f) => masteredGroup(Progress.boardId(f))).toList()
      ..sort((a, b) {
        final c = insideFirst(a, b);
        if (c != 0) return c;
        final s = (progress.boards[Progress.boardId(a)]?.solved ?? 0)
            .compareTo(progress.boards[Progress.boardId(b)]?.solved ?? 0);
        return s != 0 ? s : compareSeen(a, b);
      });
    final open = circles.where((f) => !masteredGroup(Progress.boardId(f))).toList()
      ..sort((a, b) {
        final c = insideFirst(a, b);
        if (c != 0) return c;
        final o = progress.timesOpened(Progress.boardId(a)).compareTo(progress.timesOpened(Progress.boardId(b)));
        if (o != 0) return o;
        final d = a.length.compareTo(b.length);
        return d != 0 ? d : compareSeen(a, b);
      });

    final deeper = _random.nextDouble() < _repo.settings.deeperShare;
    final List<PathFilter>? chosen = deeper
        ? (strong.isNotEmpty ? strong.first : (open.isNotEmpty ? open.first : null))
        : (open.isNotEmpty ? open.first : (strong.isNotEmpty ? strong.first : null));
    if (chosen == null) return null;
    final step = chosen.last;
    return NextStep(chosen, registry.byId(step.$1)?.label(step.$2) ?? step.$2,
        inside: inside(chosen), mastered: masteredGroup(Progress.boardId(chosen)));
  }

  /// The button that ends a board: to the board chosen for him, or, when nothing was
  /// chosen, a parallel board at once, so he never waits.
  void goNext() {
    final step = nextStep;
    if (step == null) {
      nextBoard();
    } else {
      _goTo(step.filter);
    }
  }

  // ---------------------------------------------------------------------- actions

  Future<void> init() async {
    await _repo.load();
    progress = await _progressStore.load();
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
    final b = _repo.assembler.makeBoard(BoardContext(
        filter: lvl.filter,
        dimension: lvl.dim,
        preferValues: _repo.settings.keepInPlay[lvl.dim.id] ?? const [],
        lastTiles: _lastTiles));
    if (b != null) _lastTiles = {for (final e in b.tiles) e.id};

    board = b;
    atFloor = b == null;
    solved.clear();
    selected.clear();
    mistakes = 0;
    _order = b == null ? [] : [...b.tiles];
    message = '';
    _clueGroup = null;
    _clueStep = -1;
    clue = null;
    cluesUsed = 0;
    _shaken.clear();
    _clued.clear();
    nextStep = null;
    explanation = null;
    if (b != null) {
      progress.opened(Progress.boardId(lvl.filter), _now());
      unawaited(_progressStore.save(progress));
    }
    notifyListeners();
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
      progress.found(Progress.boardId(_childFilter(g)), _now(),
          clean: !_shaken.contains(g.value) && !_clued.contains(g.value));
      explanation = explanationOf(g);
      if (g.value == _clueGroup) {
        _clueGroup = null;
        _clueStep = -1;
        clue = null;
      }
      if (boardFinished) {
        progress.solved(Progress.boardId(_stack.last.filter), _now());
        // Nowhere deeper to go from here: an order for more content, which the job reads.
        if (diggable.isEmpty) progress.order(Progress.boardId(_stack.last.filter), _now());
        unawaited(_progressStore.save(progress));
        nextStep = _chooseNext();
        message = 'Solved!';
        notifyListeners();
        return SubmitResult.roundDone;
      }
      unawaited(_progressStore.save(progress));
      message = 'Yes! ${g.label}';
      notifyListeners();
      return SubmitResult.correct;
    }

    mistakes++;
    for (final g in b.groups) {
      if (!_isSolvedGroup(g) && g.items.any((e) => ids.contains(e.id))) _shaken.add(g.value);
    }
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

  /// A parallel board, so that he never waits: another circle at the same depth, the one
  /// he has seen least recently. If there is no other, this circle again with other things.
  void nextBoard() {
    final depth = _stack.length - 1;
    final here = Progress.boardId(_stack.last.filter);
    final others = _repo.assembler
        .circlesAtDepth(depth, _stack.first.dim, needPictures: _repo.settings.boardsNeedPictures)
        .where((filter) => Progress.boardId(filter) != here)
        .toList();
    if (others.isEmpty) {
      _open();
      return;
    }
    final never = DateTime.fromMillisecondsSinceEpoch(0);
    others.sort((a, b) => (progress.lastSeen(Progress.boardId(a)) ?? never)
        .compareTo(progress.lastSeen(Progress.boardId(b)) ?? never));
    _goTo(others.first);
  }

  /// Stand at the circle [filter] leads to, with the way back to the seed intact.
  void _goTo(List<PathFilter> filter) {
    final seed = _stack.first;
    _stack
      ..clear()
      ..add(seed);
    for (int i = 0; i < filter.length; i++) {
      final path = filter.sublist(0, i + 1);
      final dims = _repo.assembler.boardableDimensions(path);
      if (dims.isEmpty) break;
      final step = filter[i];
      _stack.add(_Level(path, dims.first, registry.byId(step.$1)?.label(step.$2) ?? step.$2));
    }
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
