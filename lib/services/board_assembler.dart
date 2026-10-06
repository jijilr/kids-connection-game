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

  const Board({
    required this.dimension,
    required this.groups,
    required this.tiles,
    required this.filter,
  });
}

/// Builds 4×4 boards from the cached graph — pure, deterministic, no LLM (PRD VI.0:
/// "cache the graph, not the boards"). Boards are assembled fresh on demand.
class BoardAssembler {
  final List<Entity> entities;
  final DimensionRegistry registry;
  final Random _random;

  /// Entities to favour when several could fill a slot — e.g. "has a picture", so a
  /// board never mixes picture tiles with bare-text tiles in a way that gives a group
  /// away (a style difference must never be the answer).
  bool Function(Entity)? preferred;

  BoardAssembler(this.entities, this.registry, {Random? random, this.preferred})
      : _random = random ?? Random();

  bool _pref(Entity e) => preferred?.call(e) ?? true;

  /// Preferred first, then most familiar (mundane-first, PRD IV.3).
  int _rank(Entity a, Entity b) {
    final pa = _pref(a), pb = _pref(b);
    if (pa != pb) return pa ? -1 : 1;
    return b.familiar.compareTo(a.familiar);
  }

  /// Things this close to the best-known candidate count as equally familiar.
  static const _aboutAsFamiliar = 0.1;

  /// Pick [n] from [cands]: preferred + well-known first. The pool is every preferred
  /// candidate about as familiar as the best one (never fewer than n + 2), so boards
  /// vary without reaching for obscure things.
  List<Entity> _pick(List<Entity> cands, int n) {
    final sorted = [...cands]..sort(_rank);
    final prefCount = sorted.where(_pref).length;
    if (prefCount <= n) return sorted.take(n).toList();
    final best = sorted.first.familiar;
    final close = sorted
        .take(prefCount)
        .where((e) => best - e.familiar <= _aboutAsFamiliar)
        .length;
    final pool = sorted.take(max(close, min(prefCount, n + 2))).toList()..shuffle(_random);
    return pool.take(n).toList();
  }

  List<Entity> _filtered(List<PathFilter> filter) =>
      entities.where((e) => filter.every((f) => e.isIn(f.$1, f.$2))).toList();

  /// Build a 4×4 board over [filter], sorted by [dimension].
  /// Returns null if fewer than 4 values have >= 4 members (can't fill a 4×4 —
  /// the combinatorial/recognition floor, PRD IV.3).
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
    final usable = byValue.entries.where((e) => e.value.length >= 4).toList();
    if (usable.length < 4) return null;

    usable.shuffle(_random);
    // Values with 4+ preferred members first, and any explicitly wanted values
    // (e.g. keep "dinosaur" on the board so digging deeper stays possible).
    int tier(MapEntry<String, List<Entity>> v) =>
        (preferValues.contains(v.key) ? 0 : 2) +
        (v.value.where(_pref).length >= 4 ? 0 : 1);
    usable.sort((a, b) => tier(a).compareTo(tier(b)));
    final chosen = usable.take(4);

    final groups = <BoardGroup>[];
    final tiles = <Entity>[];
    for (final entry in chosen) {
      final four = _pick(entry.value, 4);
      groups.add(BoardGroup(
        dimId: dimension.id,
        value: entry.key,
        label: dimension.label(entry.key),
        items: four,
      ));
      tiles.addAll(four);
    }
    tiles.shuffle(_random);
    return Board(dimension: dimension, groups: groups, tiles: tiles, filter: filter);
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
