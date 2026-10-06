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

  const BoardContext({
    this.filter = const [],
    this.dimension,
    this.preferValues = const [],
    this.lastTiles = const {},
  });
}

/// Builds 4×4 boards from the cached graph — pure, deterministic, no LLM (PRD VI.0:
/// "cache the graph, not the boards"). Boards are assembled fresh on demand.
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
        if (shown.length >= 4) usable[value] = shown;
      });
      if (usable.length < 4) continue;

      // Hard rule: exactly one clean solution. Rebuild until no other field also
      // splits these 16 tiles four by four, then give up on this style.
      for (int attempt = 0; attempt < _maxRebuilds; attempt++) {
        // When all four groups share a sub-kind field, spreading each one evenly builds
        // a perfect grid — itself a second solution. So the later attempts mix less evenly.
        final evenSpread = attempt < _maxRebuilds ~/ 2;
        // Any explicitly wanted values first (e.g. keep "dinosaur" on the board).
        final values = usable.keys.toList()..shuffle(_random);
        values.sort((a, b) => (preferValues.contains(a) ? 0 : 1)
            .compareTo(preferValues.contains(b) ? 0 : 1));

        final groups = <BoardGroup>[];
        final tiles = <Entity>[];
        for (final value in values.take(4)) {
          final sub = _subKind(byValue[value]!, dimension, filter);
          final four = sub == null
              ? _pick(usable[value]!, 4)
              : evenSpread
                  ? _pickSpread(usable[value]!, 4, sub)
                  : _pickMixed(usable[value]!, 4, sub);
          groups.add(BoardGroup(
            dimId: dimension.id,
            value: value,
            label: dimension.label(value),
            items: four,
          ));
          tiles.addAll(four);
        }
        if (secondSolution(tiles, dimension) != null) continue;
        tiles.shuffle(_random);
        return Board(
            dimension: dimension, groups: groups, tiles: tiles, filter: filter, style: style);
      }
    }
    return null;
  }

  static const _maxRebuilds = 20;

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
          filter: context.filter, dimension: dimension, preferValues: context.preferValues);
      if (board == null) return null;
      final repeated = board.tiles.where((e) => context.lastTiles.contains(e.id)).length;
      if (repeated < board.tiles.length) return board; // not the very same sixteen again
    }
    return board;
  }

  /// Every circle [depth] steps from the seed that can make a board now, as the path
  /// that leads to it. With [needPictures], only those that can be drawn in pictures.
  List<List<PathFilter>> circlesAtDepth(int depth, Dimension start, {bool needPictures = true}) {
    var level = <List<PathFilter>>[const []];
    for (int step = 0; step < depth; step++) {
      final next = <List<PathFilter>>[];
      for (final filter in level) {
        final sortedBy = filter.isEmpty ? start : boardableDimensions(filter).first;
        for (final value in sortedBy.values.keys) {
          final child = <PathFilter>[...filter, (sortedBy.id, value)];
          final inside = boardableDimensions(child);
          if (inside.isEmpty) continue;
          if (needPictures && !hasPictureBoard(child, inside.first)) continue;
          next.add(child);
        }
      }
      level = next;
    }
    return level;
  }

  /// Whether a board over [filter] sorted by [dimension] can be drawn in one picture
  /// style throughout, rather than with names only.
  bool hasPictureBoard(List<PathFilter> filter, Dimension dimension) {
    final pool = _filtered(filter);
    return styles.any((shows) {
      final counts = <String, int>{};
      for (final e in pool.where(shows)) {
        final v = e.valueFor(dimension.id);
        if (v != null && dimension.values.containsKey(v)) counts[v] = (counts[v] ?? 0) + 1;
      }
      return counts.values.where((c) => c >= 4).length >= 4;
    });
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
        if (v != null && d.values.containsKey(v)) {
          counts[v] = (counts[v] ?? 0) + 1;
        }
      }
      if (counts.values.where((c) => c >= 4).length >= 4) out.add(d);
    }
    return out;
  }
}
