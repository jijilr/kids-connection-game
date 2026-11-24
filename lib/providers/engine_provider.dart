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

/// One knot of the web of what he has found: the first set, or a group he has found. Its
/// parent is the set it was found in.
class WebNode {
  final String id;
  final String label;
  final String? parent;
  final int found;
  final int clean;

  /// The app will follow this line next: he did the group well and has not played its set.
  final bool line;

  /// A picture of one thing of the group, for a child who cannot read its name.
  final EntityMedia? picture;

  /// Nothing lies below this group: the end of a branch. The world holds too few such
  /// things to sort them further.
  final bool end;

  /// For the group "in between": the knots it lies between, on the same set. It is tied
  /// to them as well as to its set, so such a knot is a bridge between branches.
  final List<String> between;

  const WebNode(this.id, this.label, this.parent,
      {this.found = 0,
      this.clean = 0,
      this.line = false,
      this.picture,
      this.end = false,
      this.between = const []});

  bool get isStart => parent == null;
}

/// How wide and how deep his web is (the owner's two measures of 24 Nov 2026), counted on
/// the web itself and not on any list of subjects of ours. An end is a knot with nothing
/// found beyond it. Breadth is the number of ends. Depth is the number of steps from the
/// middle to an end: its average, and the deepest. A step is one of this game's own
/// questions, so the numbers show how his web grows; they are not a measure of how much
/// he knows.
class WebMeasure {
  final int ends;
  final double averageDepth;
  final int deepest;
  const WebMeasure(this.ends, this.averageDepth, this.deepest);
}

WebMeasure measureWeb(List<WebNode> nodes) {
  final parents = {for (final n in nodes) if (n.parent != null) n.parent!};
  final depths = [
    for (final n in nodes)
      if (!n.isStart && !parents.contains(n.id)) n.id.split('/').length
  ];
  if (depths.isEmpty) return const WebMeasure(0, 0, 0);
  return WebMeasure(depths.length, depths.reduce((a, b) => a + b) / depths.length, depths.reduce(max));
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

  /// The app chooses the way by itself: what it is designed for (the owner's word of
  /// 24 Nov 2026: "dig deeper is not a choice for the user. this is a test feature... the
  /// dig deeper is done by the app"). On by default. Switched off, the test features show:
  /// "Dig deeper" on each group, Back, a new set at will.
  bool automate = true;

  Future<void> setAutomate(bool on) async {
    automate = on;
    notifyListeners();
    await _progressStore.saveFlag('automate', on);
  }

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

  // The kinds of this set's place that he had been tested on when the set opened, and
  // the places where a set tested no new kind although one was untested: such a place
  // is not offered again in this sitting, so he is never sent round in a ring.
  Set<String> _testedAtOpen = {};
  final Set<String> _noNewKind = {};

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

  /// The web of what he has found so far, for the web screen: the first set, and every
  /// group he has found, each joined to the set it was found in. Nothing he has not met
  /// is in it, so it only grows. A group whose place in the game can no longer be worked
  /// out (its question was withdrawn) is left out.
  List<WebNode> get web {
    final start = _stack.isEmpty ? null : _stack.first;
    if (start == null) return const [];
    final nodes = <String, WebNode>{'seed': WebNode('seed', start.label, null)};
    final ids = progress.groups.keys.where((id) => (progress.groups[id]?.found ?? 0) > 0).toList()
      ..sort((a, b) => a.split('/').length.compareTo(b.split('/').length));
    for (final id in ids) {
      final values = id.split('/');
      var dim = start.dim;
      final filter = <PathFilter>[];
      String? label;
      for (int i = 0; i < values.length; i++) {
        if (!dim.values.containsKey(values[i])) {
          label = null;
          break;
        }
        label = dim.label(values[i]);
        filter.add((dim.id, values[i]));
        final here = values.sublist(0, i + 1).join('/');
        if (!nodes.containsKey(here)) {
          // a set he went through without having found its group: a plain knot on the way
          final seen = progress.groups[here];
          final pool = _repo.entities.where((e) => filter.every((f) => e.isIn(f.$1, f.$2)));
          final shown = pool.map(_repo.media.forEntity).where((m) => m.art != null || m.image != null);
          final before = values.sublist(0, i);
          final sides = <String>{};
          if (values[i] == Dimension.inBetween) {
            for (final e in pool) {
              final named = e.sidesOf(dim.id);
              sides.addAll(named.isEmpty ? dim.kinds : named);
            }
          }
          nodes[here] = WebNode(here, label, i == 0 ? 'seed' : before.join('/'),
              found: seen?.found ?? 0,
              clean: seen?.clean ?? 0,
              line: progress.lines.contains(here),
              picture: shown.isEmpty ? null : shown.first,
              end: dim.ends.containsKey(values[i]),
              between: [for (final side in sides) [...before, side].join('/')]);
        }
        if (i < values.length - 1) {
          final inside = _repo.assembler.boardableDimensions(filter);
          if (inside.isEmpty) {
            label = null;
            break;
          }
          dim = inside.first;
        }
      }
    }
    return nodes.values.toList();
  }

  /// The knots of his web he has not been shown yet, nearest the middle first.
  List<String> get newKnots => [
        for (final n in web)
          if (!n.isStart && !progress.webSeen.contains(n.id)) n.id
      ];

  /// He has been shown the web as it stands.
  void markWebSeen() {
    final before = progress.webSeen.length;
    progress.webSeen.addAll(web.where((n) => !n.isStart).map((n) => n.id));
    if (progress.webSeen.length == before) return;
    unawaited(_progressStore.save(progress));
    notifyListeners();
  }

  // "Your web grew": after a few sets in one sitting the web opens by itself, if it has grown.
  int _setsThisSitting = 0;
  int _momentShownAt = 0;

  /// It is time to show him his web before the next set.
  bool get webMomentDue {
    final every = _repo.settings.webAfterSets;
    return every > 0 &&
        _setsThisSitting > 0 &&
        _setsThisSitting % every == 0 &&
        _momentShownAt != _setsThisSitting &&
        newKnots.isNotEmpty;
  }

  void webMomentShown() => _momentShownAt = _setsThisSitting;

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
    // A set he has played stays a line while one of its kinds is untested: so the first
    // set, and the one he has just finished, may come again.
    final ready = [
      if (progress.lines.contains('seed')) const <PathFilter>[],
      ..._repo.assembler
          .circlesBelow(_stack.first.dim, needPictures: _repo.settings.boardsNeedPictures),
    ].where((f) => Progress.boardId(f) != here || progress.lines.contains(here)).toList();
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
    final label = chosen.isEmpty
        ? _stack.first.label
        : registry.byId(chosen.last.$1)?.label(chosen.last.$2) ?? chosen.last.$2;
    return NextStep(chosen, label,
        inside: inside(chosen), proven: progress.lines.contains(Progress.boardId(chosen)));
  }

  // ------------------------------------------------- more kinds than four, and "in between"

  /// What he has shown of the kinds of the set at [filter], sorted by [dim]: how well he
  /// has done each kind he was tested on, the things each was last shown with, and the
  /// kinds that are not to be shown yet.
  ({Map<String, double> tested, Map<String, Set<String>> shown, Set<String> notYet}) _coverage(
      List<PathFilter> filter, Dimension dim) {
    final tested = <String, double>{};
    final shown = <String, Set<String>>{};
    for (final value in dim.values.keys) {
      final g = progress.groups[Progress.boardId([...filter, (dim.id, value)])];
      if (g == null || g.found == 0) continue;
      tested[value] = g.howWell;
      shown[value] = g.things.toSet();
    }
    return (tested: tested, shown: shown, notYet: _notYet(filter, dim));
  }

  /// "In between" waits until he knows the kinds on both sides of it (the owner's rule
  /// that new things extend what he has seen: a thing that fits no kind means nothing to
  /// one who does not know the kinds). The sides are the answers its things lie between;
  /// a thing that names none (the people who know do not agree) lies between them all.
  Set<String> _notYet(List<PathFilter> filter, Dimension dim) {
    if (!dim.values.containsKey(Dimension.inBetween)) return const {};
    final between = _repo.entities.where((e) =>
        filter.every((f) => e.isIn(f.$1, f.$2)) && e.valueFor(dim.id) == Dimension.inBetween);
    if (between.isEmpty) return const {};
    final ready = _repo.assembler.kindsReady(filter, dim).where((v) => v != Dimension.inBetween).toSet();
    final sides = <String>{};
    for (final e in between) {
      final named = e.sidesOf(dim.id);
      sides.addAll(named.isEmpty ? ready : named.where(ready.contains));
    }
    return sides.every((side) => _knows([...filter, (dim.id, side)]))
        ? const {}
        : const {Dimension.inBetween};
  }

  /// He knows the group at [side]: he has found it, and where it has a set of its own he
  /// has played that set through.
  bool _knows(List<PathFilter> side) {
    final id = Progress.boardId(side);
    if ((progress.groups[id]?.found ?? 0) == 0) return false;
    final inside = _repo.assembler.boardableDimensions(side);
    final hasSet = inside.isNotEmpty &&
        (!_repo.settings.boardsNeedPictures || _repo.assembler.hasPictureBoard(side, inside.first));
    return !hasSet || (progress.boards[id]?.solved ?? 0) > 0;
  }

  /// The sets he has played in which a kind is still untested and can be shown now.
  List<String> _unfinished() {
    final start = _stack.first;
    final out = <String>[];
    final places = [
      const <PathFilter>[],
      ..._repo.assembler.circlesBelow(start.dim, needPictures: _repo.settings.boardsNeedPictures),
    ];
    for (final filter in places) {
      final id = Progress.boardId(filter);
      if (_noNewKind.contains(id) || (progress.boards[id]?.solved ?? 0) == 0) continue;
      final dim = filter.isEmpty ? start.dim : _repo.assembler.boardableDimensions(filter).first;
      final c = _coverage(filter, dim);
      final ready = _repo.assembler.kindsReady(filter, dim);
      if (ready.any((v) => !c.tested.containsKey(v) && !c.notYet.contains(v))) out.add(id);
    }
    return out;
  }

  /// Whether the group [g] of the set just played leads on to a set of its own, made or
  /// still to be made. The end of a branch does not; "in between" does only where its
  /// things can themselves be sorted.
  bool _leadsOn(Board b, BoardGroup g) =>
      !b.dimension.ends.containsKey(g.value) && (g.value != Dimension.inBetween || canDescend(g));

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
    automate = await _progressStore.loadFlag('automate', otherwise: true);
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
    final known = _coverage(lvl.filter, lvl.dim);
    _testedAtOpen = known.tested.keys.toSet();
    final b = _repo.assembler.makeBoard(BoardContext(
        filter: lvl.filter,
        dimension: lvl.dim,
        preferValues: _repo.settings.keepInPlay[lvl.dim.id] ?? const [],
        lastTiles: _lastTiles,
        tested: known.tested,
        shownBefore: known.shown,
        notYet: known.notYet));
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
      progress.found(Progress.boardId(_childFilter(g)), _now(),
          clean: didWell(g),
          wrong: _wrongGuesses[g.value] ?? 0,
          things: [for (final e in g.items) e.id]);
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
        // The lines to follow next: the groups he did well go first. The set itself is
        // used up only when every kind of its place has been tested; a set that tested no
        // new kind is not offered again in this sitting.
        String idOf(BoardGroup g) => Progress.boardId(_childFilter(g));
        final hereId = Progress.boardId(_stack.last.filter);
        if (b.groups.every((g) => _testedAtOpen.contains(g.value))) _noNewKind.add(hereId);
        progress.finished(hereId,
            all: [for (final g in b.groups) idOf(g)],
            didWell: [for (final g in ranked) if (didWell(g) && _leadsOn(b, g)) idOf(g)],
            unfinished: _unfinished());
        unawaited(_progressStore.save(progress));
        _setsThisSitting++;
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
