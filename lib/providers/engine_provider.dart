import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/entity.dart';
import '../models/dimension.dart';
import '../models/group_words.dart';
import '../services/board_assembler.dart';
import '../services/content_repository.dart';
import '../services/live_link.dart';
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

  /// It follows a line he has shown: the set inside a group he did well (the four in
  /// five). False when it is a set he has not proven (the one in five, or when no line
  /// he has shown is ready).
  final bool proven;

  const NextStep(this.filter, this.label, {required this.inside, required this.proven});

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
    LiveLink? live,
  })  : _repo = repo ?? ContentRepository(),
        _random = random ?? Random(),
        _progressStore = progressStore ?? MemoryProgressStore(),
        _now = clock ?? DateTime.now,
        _live = live;

  /// The link to the helper on the owner's PC, which makes sets ahead of him. Null where
  /// there is none: the game then plays from what it ships with.
  final LiveLink? _live;
  String? _liveVersion;
  double? _roll; // the dice for this set's next step, thrown once

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

  // On this set, for each group: how many wrong guesses took in one of its things, the
  // number of the guess that first took it in (so that "attempted earliest" is known),
  // and whether a clue was asked for it.
  final Map<String, int> _wrongGuesses = {};
  final Map<String, int> _firstAttempt = {};
  final Set<String> _clued = {};
  int _guesses = 0;

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

  /// The groups of this set in the order he did them best (the owner's rule of 24 Nov
  /// 2026): fewest wrong guesses that took in its things, then no clue, and a tie goes
  /// to the one he attempted earliest.
  List<BoardGroup> get ranked => [...solved]..sort((a, b) {
      final w = (_wrongGuesses[a.value] ?? 0).compareTo(_wrongGuesses[b.value] ?? 0);
      if (w != 0) return w;
      final c = (_clued.contains(a.value) ? 1 : 0).compareTo(_clued.contains(b.value) ? 1 : 0);
      if (c != 0) return c;
      final t = (_firstAttempt[a.value] ?? 0).compareTo(_firstAttempt[b.value] ?? 0);
      return t != 0 ? t : solved.indexOf(a).compareTo(solved.indexOf(b)); // the same guess: the one found first
    });

  /// He did this group well: no wrong guess took in its things, and no clue was asked.
  bool didWell(BoardGroup g) => (_wrongGuesses[g.value] ?? 0) == 0 && !_clued.contains(g.value);

  /// Where the button that ends a set leads (the owner's design of 24 Nov 2026). There
  /// is one game and its data grows: the lines he has shown, best first, are kept in his
  /// saved progress, and the helper on the owner's PC prepares the sets they lead to, a
  /// few ahead of him. Four times in five the button follows the first of those lines
  /// whose set is ready. Once in five it leads to a set he has not proven: the one he
  /// has opened least, nearest first. When no line is ready he goes there too, so he
  /// never waits.
  NextStep? _chooseNext() {
    final hereFilter = _stack.last.filter;
    final here = Progress.boardId(hereFilter);
    final ready = _repo.assembler
        .circlesBelow(_stack.first.dim, needPictures: _repo.settings.boardsNeedPictures)
        .where((f) => Progress.boardId(f) != here)
        .toList();
    bool inside(List<PathFilter> f) =>
        f.length == hereFilter.length + 1 &&
        Progress.boardId(f.sublist(0, hereFilter.length)) == here &&
        solved.any((g) => g.dimId == f.last.$1 && g.value == f.last.$2);
    final byId = {for (final f in ready) Progress.boardId(f): f};
    final shown = [for (final id in progress.lines) if (byId.containsKey(id)) byId[id]!];
    final never = DateTime.fromMillisecondsSinceEpoch(0);
    final rest = ready.where((f) => !progress.lines.contains(Progress.boardId(f))).toList()
      ..sort((a, b) {
        final o = progress.timesOpened(Progress.boardId(a)).compareTo(progress.timesOpened(Progress.boardId(b)));
        if (o != 0) return o;
        final d = a.length.compareTo(b.length);
        if (d != 0) return d;
        final t = (progress.lastSeen(Progress.boardId(a)) ?? never)
            .compareTo(progress.lastSeen(Progress.boardId(b)) ?? never);
        return t != 0 ? t : ready.indexOf(a).compareTo(ready.indexOf(b));
      });

    final follow = (_roll ??= _random.nextDouble()) < _repo.settings.deeperShare;
    final List<PathFilter>? chosen = follow
        ? (shown.isNotEmpty ? shown.first : (rest.isNotEmpty ? rest.first : null))
        : (rest.isNotEmpty ? rest.first : (shown.isNotEmpty ? shown.first : null));
    if (chosen == null) return null;
    final step = chosen.last;
    return NextStep(chosen, registry.byId(step.$1)?.label(step.$2) ?? step.$2,
        inside: inside(chosen), proven: progress.lines.contains(Progress.boardId(chosen)));
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
    final live = _live;
    if (live != null) {
      // the data as it stands now on the owner's PC, with every set made so far
      final now = await live.state();
      if (now != null && await _repo.loadLive(live, now)) _liveVersion = now.version;
    }
    final start = _repo.settings;
    _stack
      ..clear()
      ..add(_Level(const [], registry.byId(start.startField)!, start.startLabel));
    _open();
    isLoading = false;
    notifyListeners();
    unawaited(syncLive());
  }

  /// Tell the helper where he is, and take up whatever it has made since: a set he
  /// earned may have become ready while he played another. Called when a set is
  /// finished. Without a helper it does nothing.
  Future<void> syncLive() async {
    final live = _live;
    if (live == null) return;
    final dead = await live.send(progress);
    if (dead.any(progress.lines.contains)) {
      progress.drop(dead);
      unawaited(_progressStore.save(progress));
    }
    final now = await live.state();
    if (now == null) return;
    if (now.version != _liveVersion && await _repo.loadLive(live, now)) {
      _liveVersion = now.version;
      for (int i = 0; i < _stack.length; i++) {
        final lvl = _stack[i];
        _stack[i] = _Level(lvl.filter, registry.byId(lvl.dim.id) ?? lvl.dim, lvl.label);
      }
    }
    if (boardFinished) {
      nextStep = _chooseNext();
      notifyListeners();
    }
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
    _wrongGuesses.clear();
    _firstAttempt.clear();
    _clued.clear();
    _guesses = 0;
    _roll = null;
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
    _guesses++;
    for (final g in b.groups) {
      if (!_isSolvedGroup(g) && g.items.any((e) => ids.contains(e.id))) {
        _firstAttempt.putIfAbsent(g.value, () => _guesses);
      }
    }

    for (final g in b.groups) {
      if (_isSolvedGroup(g) || !_same(g, ids)) continue;
      solved.add(g);
      selected.clear();
      progress.found(Progress.boardId(_childFilter(g)), _now(), clean: didWell(g));
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
        // the lines to follow next: this set is used up; the groups he did well go first
        String idOf(BoardGroup g) => Progress.boardId(_childFilter(g));
        progress.finished(Progress.boardId(_stack.last.filter),
            all: [for (final g in b.groups) idOf(g)],
            didWell: [for (final g in ranked) if (didWell(g)) idOf(g)]);
        unawaited(_progressStore.save(progress));
        nextStep = _chooseNext();
        message = 'Solved!';
        notifyListeners();
        unawaited(syncLive());
        return SubmitResult.roundDone;
      }
      unawaited(_progressStore.save(progress));
      message = 'Yes! ${g.label}';
      notifyListeners();
      return SubmitResult.correct;
    }

    mistakes++;
    for (final g in b.groups) {
      if (!_isSolvedGroup(g) && g.items.any((e) => ids.contains(e.id))) {
        _wrongGuesses[g.value] = (_wrongGuesses[g.value] ?? 0) + 1;
      }
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
