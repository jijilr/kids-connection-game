import 'dart:math';
import '../models/entity.dart';
import '../models/dimension.dart';

/// A filter step in the traversal path: (dimensionId, value), e.g. ("category","dinosaur").
typedef PathFilter = (String, String);

/// One solvable group on a board: 4 entities sharing (dimId == value).
class BoardGroup {
  final String dimId;
  final String value;
  final String label; // "Dinosaurs"
  final List<Entity> items; // 4
  const BoardGroup({
    required this.dimId,
    required this.value,
    required this.label,
    required this.items,
  });
}

/// A 4×4 board: 4 groups of 4, sorted by [dimension], over an accumulated [filter].
class Board {
  final Dimension dimension;
  final List<BoardGroup> groups; // 4
  final List<Entity> tiles; // 16, shuffled
  final List<PathFilter> filter;

  /// Which of the assembler's styles every tile on this board is drawn in, or null
  /// when no single style covers all 16 and the board shows names only.
  final int? style;

  const Board({
    required this.dimension,
    required this.groups,
    required this.tiles,
    required this.filter,
    this.style,
  });
}

/// What a board is wanted for: the circle it is drawn from, and what to steer clear of.
class BoardContext {
  /// The steps that lead to the circle; empty for the seed.
  final List<PathFilter> filter;

  /// The field to sort by. Null takes the circle's own: the first that can fill a board.
  final Dimension? dimension;
  final List<String> preferValues;

  /// The tiles of the board just played, so that a fresh board is not the same sixteen.
  final Set<String> lastTiles;

  /// How well he has done each kind of this circle so far, from 0 to 1. A kind that is
  /// not in here has not been tested yet. Null when nothing is known: any four will do.
  ///
  /// A circle may hold more kinds than the four a set shows (the owner's ruling of 24 Nov
  /// 2026). They are covered in the fewest sets: the untested kinds come first, and the
  /// places left over are filled with kinds already used, the ones he did worst first.
  /// Five kinds take two sets (four, then the one left with three used again); six take
  /// two (four, then the two left with two used again).
  final Map<String, double>? tested;

  /// For a kind: the things it was last shown with. A kind that is used again is shown
  /// with other things where it has them.
  final Map<String, Set<String>> shownBefore;

  /// Kinds that are not to be shown yet: "in between", until he knows the kinds on both
  /// sides of it.
  final Set<String> notYet;

  const BoardContext({
    this.filter = const [],
    this.dimension,
    this.preferValues = const [],
    this.lastTiles = const {},
    this.tested,
    this.shownBefore = const {},
    this.notYet = const {},
  });
}

/// Builds 4×4 boards from the cached graph — pure, deterministic, no LLM (PRD VI.0:
/// "cache the graph, not the boards"). Boards are assembled fresh on demand.
///
/// It makes sets and nothing else. Which places there are, what is asked at each and
/// which kinds can be shown is not worked out here: the game reads that from the map of
/// places (lib/models/places_map.dart), built by tools/catalogue/places.py, where those
/// rules are written once (the owner, 24 Nov 2026: the map is "the nerve system").
class BoardAssembler {
  final List<Entity> entities;
  final DimensionRegistry registry;
  final Random _random;

  /// The ways a tile can be drawn, best first (e.g. photo, then emoji); each says
  /// whether a thing can be drawn that way. A board uses ONE style for all 16 tiles,
  /// so a tile's look never gives its group away.
  final List<bool Function(Entity)> styles;

  /// (field, values) kept off every board for now, e.g. a kind with too few familiar
  /// things to form a group of its own.
  final Map<String, List<String>> heldBack;

  BoardAssembler(
    this.entities,
    this.registry, {
    Random? random,
    this.styles = const [],
    this.heldBack = const {},
  }) : _random = random ?? Random();

  /// Things this close to the best-known candidate count as equally familiar.
  static const _aboutAsFamiliar = 0.1;

  /// Pick [n] from [cands], most familiar first (mundane-first, PRD IV.3). The pool is
  /// every candidate about as familiar as the best one (never fewer than n + 2), so
  /// boards vary without reaching for obscure things.
  List<Entity> _pick(List<Entity> cands, int n) {
    final sorted = [...cands]..sort((a, b) => b.familiar.compareTo(a.familiar));
    if (sorted.length <= n) return sorted;
    final best = sorted.first.familiar;
    final close = sorted.where((e) => best - e.familiar <= _aboutAsFamiliar).length;
    final pool = sorted.take(max(close, min(sorted.length, n + 2))).toList()
      ..shuffle(_random);
    return pool.take(n).toList();
  }

  /// Pick [n] from [cands] across as many different [sub] kinds as possible: every kind
  /// is used once before any is used twice, so no group is filled by one sub-kind.
  List<Entity> _pickSpread(List<Entity> cands, int n, Dimension sub) {
    final byKind = <String, List<Entity>>{};
    for (final e in cands) {
      byKind.putIfAbsent(e.valueFor(sub.id)!, () => []).add(e);
    }
    final kinds = byKind.keys.toList()..shuffle(_random);
    final picked = <Entity>[];
    while (picked.length < n) {
      for (final kind in kinds) {
        if (picked.length == n) break;
        final left = byKind[kind]!.where((e) => !picked.contains(e)).toList();
        if (left.isNotEmpty) picked.addAll(_pick(left, 1));
      }
    }
    return picked;
  }

  /// Pick [n] without an even spread, but still from more than one [sub] kind where
  /// the candidates allow it.
  List<Entity> _pickMixed(List<Entity> cands, int n, Dimension sub) {
    var picked = _pick(cands, n);
    for (int i = 0; i < 10; i++) {
      if (picked.map((e) => e.valueFor(sub.id)).toSet().length > 1) break;
      picked = _pick(cands, n);
    }
    return picked;
  }

  /// The field that splits a group into sub-kinds: one that could sort a board of its
  /// own and that every member of the group carries (kind of animal, for Animals).
  Dimension? _subKind(List<Entity> members, Dimension of, List<PathFilter> filter) {
    for (final d in registry.boardable) {
      if (d.id == of.id || filter.any((f) => f.$1 == d.id)) continue;
      if (members.every((e) => e.fields.containsKey(d.id))) return d;
    }
    return null;
  }

  /// Every four of [kinds], the best first.
  ///
  /// With [tested] (how well he has done each kind so far; a kind not in it is untested):
  /// the four with the most untested kinds first, so that every kind is covered in the
  /// fewest sets; among those, the four whose used-again kinds he did worst. The order is
  /// also the way out when a four cannot make a set with exactly one clean solution: the
  /// same four are tried with other things first (by the caller), then a four with another
  /// used-again kind, and only then a four with fewer untested kinds, which costs him one
  /// more set and never the one-solution rule. [prefer] decides between fours that are
  /// otherwise alike, and chance decides the rest, so sets vary.
  List<List<String>> _fours(List<String> kinds, Map<String, double>? tested, List<String> prefer) {
    final k = [...kinds]..shuffle(_random);
    final all = <List<String>>[];
    for (int a = 0; a < k.length; a++) {
      for (int b = a + 1; b < k.length; b++) {
        for (int c = b + 1; c < k.length; c++) {
          for (int d = c + 1; d < k.length; d++) {
            all.add([k[a], k[b], k[c], k[d]]);
          }
        }
      }
    }
    int fresh(List<String> four) =>
        tested == null ? 0 : four.where((v) => !tested.containsKey(v)).length;
    double known(List<String> four) =>
        tested == null ? 0 : four.fold(0.0, (sum, v) => sum + (tested[v] ?? 0));
    int wanted(List<String> four) => four.where(prefer.contains).length;
    final order = {for (int i = 0; i < all.length; i++) all[i]: i};
    all.sort((x, y) {
      final f = fresh(y).compareTo(fresh(x));
      if (f != 0) return f;
      final w = known(x).compareTo(known(y));
      if (w != 0) return w;
      final p = wanted(y).compareTo(wanted(x));
      return p != 0 ? p : order[x]!.compareTo(order[y]!);
    });
    return all;
  }

  /// Four things for one group. A kind he has been shown before is shown with other
  /// things where it has them: [seen] are the things it had last time.
  List<Entity> _fourOf(List<Entity> pool, Dimension? sub, bool evenSpread, Set<String> seen) {
    List<Entity> pick(List<Entity> from) => sub == null
        ? _pick(from, 4)
        : evenSpread
            ? _pickSpread(from, 4, sub)
            : _pickMixed(from, 4, sub);
    if (seen.isEmpty) return pick(pool);
    final other = pool.where((e) => !seen.contains(e.id)).toList();
    if (other.length >= 4) return pick(other);
    final again = pool.where((e) => seen.contains(e.id)).toList();
    return [...other, ..._pick(again, 4 - other.length)];
  }

  bool _isHeldBack(Entity e) =>
      heldBack.entries.any((h) => h.value.contains(e.valueFor(h.key)));

  List<Entity> _filtered(List<PathFilter> filter) => entities
      .where((e) => !_isHeldBack(e) && filter.every((f) => e.isIn(f.$1, f.$2)))
      .toList();

  /// Build a 4×4 board over [filter], sorted by [dimension].
  /// Returns null if fewer than 4 values have >= 4 members (can't fill a 4×4 —
  /// the combinatorial/recognition floor, PRD IV.3), or if every board it can build
  /// has a second clean solution.
  Board? assemble({
    List<PathFilter> filter = const [],
    required Dimension dimension,
    List<String> preferValues = const [],
    Map<String, double>? tested,
    Map<String, Set<String>> shownBefore = const {},
    Set<String> notYet = const {},
  }) {
    final byValue = <String, List<Entity>>{};
    for (final e in _filtered(filter)) {
      final v = e.valueFor(dimension.id);
      if (v != null && dimension.values.containsKey(v)) {
        byValue.putIfAbsent(v, () => []).add(e);
      }
    }

    // Try each style in turn, then names only (null), and use the first in which four
    // groups can be filled entirely.
    for (final int? style in [for (int i = 0; i < styles.length; i++) i, null]) {
      bool shows(Entity e) => style == null || styles[style](e);
      final usable = <String, List<Entity>>{};
      byValue.forEach((value, members) {
        final shown = members.where(shows).toList();
        if (shown.length >= 4 && !notYet.contains(value)) usable[value] = shown;
      });
      // "In between" is a group among the real kinds; it never makes up the number.
      if (usable.keys.where((v) => v != Dimension.inBetween).length < 4) continue;

      // Which four kinds: the best four first, then the next best when a four cannot make
      // a set with exactly one clean solution (see _fours).
      for (final four in _fours(usable.keys.toList(), tested, preferValues).take(_maxFours)) {
        // Hard rule: exactly one clean solution. Rebuild until no other field also
        // splits these 16 tiles four by four, then give up on this four.
        for (int attempt = 0; attempt < _maxRebuilds; attempt++) {
          // When all four groups share a sub-kind field, spreading each one evenly builds
          // a perfect grid — itself a second solution. So the later attempts mix less evenly.
          final evenSpread = attempt < _maxRebuilds ~/ 2;
          final groups = <BoardGroup>[];
          final tiles = <Entity>[];
          for (final value in four) {
            final sub = _subKind(byValue[value]!, dimension, filter);
            final things =
                _fourOf(usable[value]!, sub, evenSpread, shownBefore[value] ?? const {});
            groups.add(BoardGroup(
              dimId: dimension.id,
              value: value,
              label: dimension.label(value),
              items: things,
            ));
            tiles.addAll(things);
          }
          if (secondSolution(tiles, dimension) != null) continue;
          tiles.shuffle(_random);
          return Board(
              dimension: dimension, groups: groups, tiles: tiles, filter: filter, style: style);
        }
      }
    }
    return null;
  }

  static const _maxRebuilds = 20;

  /// How many fours of kinds are tried before a style is given up.
  static const _maxFours = 40;

  /// THE way a board is made (the owner's ruling of 7 Oct 2026): sixteen things in four
  /// groups of four, sorted by one field, with exactly one clean solution, from what the
  /// game already holds. It serves the first board, "Dig deeper", and a parallel board at
  /// the same depth. It never pads a group and never falls back to a shallower sorting:
  /// when the circle cannot fill such a board, it returns null.
  Board? makeBoard(BoardContext context) {
    var dimension = context.dimension;
    if (dimension == null) {
      final own = boardableDimensions(context.filter);
      if (own.isEmpty) return null;
      dimension = own.first;
    }
    Board? board;
    for (int attempt = 0; attempt < 4; attempt++) {
      board = assemble(
          filter: context.filter,
          dimension: dimension,
          preferValues: context.preferValues,
          tested: context.tested,
          shownBefore: context.shownBefore,
          notYet: context.notYet);
      if (board == null) return null;
      final repeated = board.tiles.where((e) => context.lastTiles.contains(e.id)).length;
      if (repeated < board.tiles.length) return board; // not the very same sixteen again
    }
    return board;
  }

  /// Another field that ALSO splits [tiles] cleanly into four groups of four, or null.
  /// Every stored field is tried, not only the ones that sort boards. A board with a
  /// second clean solution is refused: a child sorting by what he sees could give a
  /// right answer and be marked wrong.
  Dimension? secondSolution(List<Entity> tiles, Dimension sortedBy) {
    for (final d in registry.all) {
      if (d.id == sortedBy.id || d.arity < 4) continue;
      final counts = <String, int>{};
      for (final e in tiles) {
        final v = e.valueFor(d.id);
        if (v == null || !d.values.containsKey(v)) break;
        counts[v] = (counts[v] ?? 0) + 1;
      }
      final everyTileCounted = counts.values.fold(0, (a, b) => a + b) == tiles.length;
      if (everyTileCounted && counts.length == 4 && counts.values.every((c) => c == 4)) {
        return d;
      }
    }
    return null;
  }

  /// Dimensions that can actually fill a 4×4 board over [filter] (>= 4 values,
  /// each with >= 4 members). These are the valid descend options; an
  /// empty result is the wide-shallow floor for that slice.
  List<Dimension> boardableDimensions(List<PathFilter> filter) {
    final pool = _filtered(filter);
    final out = <Dimension>[];
    for (final d in registry.all) {
      if (!d.sortsBoards) continue;
      final counts = <String, int>{};
      for (final e in pool) {
        final v = e.valueFor(d.id);
        if (v != null && v != Dimension.inBetween && d.values.containsKey(v)) {
          counts[v] = (counts[v] ?? 0) + 1;
        }
      }
      if (counts.values.where((c) => c >= 4).length >= 4) out.add(d);
    }
    return out;
  }
}
