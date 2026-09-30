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

  /// Dimensions that ALSO cleanly partition these exact tiles into 4×4 — the
  /// "regroup" lenses (same 16 animals, seen a different way).
  final List<Dimension> lenses;

  const Board({
    required this.dimension,
    required this.groups,
    required this.tiles,
    required this.filter,
    this.lenses = const [],
  });
}

/// Builds 4×4 boards from the cached graph — pure, deterministic, no LLM (PRD VI.0:
/// "cache the graph, not the boards"). Boards are assembled fresh on demand.
class BoardAssembler {
  final List<Entity> entities;
  final DimensionRegistry registry;
  final Random _random;

  BoardAssembler(this.entities, this.registry, {Random? random})
      : _random = random ?? Random();

  List<Entity> _filtered(List<PathFilter> filter) =>
      entities.where((e) => filter.every((f) => e.isIn(f.$1, f.$2))).toList();

  /// Build a 4×4 board over [filter], sorted by [dimension].
  /// Returns null if fewer than 4 values have >= 4 members (can't fill a 4×4 —
  /// the combinatorial/recognition floor, PRD IV.3).
  Board? assemble({
    List<PathFilter> filter = const [],
    required Dimension dimension,
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
    final chosen = usable.take(4);

    final groups = <BoardGroup>[];
    final tiles = <Entity>[];
    for (final entry in chosen) {
      final members = [...entry.value]..shuffle(_random);
      // mundane-first: prefer the 4 most recognizable (PRD IV.3, fame-ordering).
      members.sort((a, b) => b.recognizability.compareTo(a.recognizability));
      final four = members.take(4).toList();
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
  /// each with >= 4 members). These are the valid descend / regroup options; an
  /// empty result is the wide-shallow floor for that slice.
  List<Dimension> boardableDimensions(List<PathFilter> filter) {
    final pool = _filtered(filter);
    final out = <Dimension>[];
    for (final d in registry.all) {
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

  /// Group a FIXED set of tiles by [dim]. Returns 4 groups of 4 iff they split
  /// cleanly (every tile tagged, exactly 4 values, 4 each); else null. This is how
  /// the SAME 16 tiles get re-partitioned on regroup.
  List<BoardGroup>? partitionBy(List<Entity> tiles, Dimension dim) {
    final byValue = <String, List<Entity>>{};
    for (final e in tiles) {
      final v = e.valueFor(dim.id);
      if (v == null || !dim.values.containsKey(v)) return null;
      byValue.putIfAbsent(v, () => []).add(e);
    }
    if (byValue.length != 4 || byValue.values.any((g) => g.length != 4)) return null;
    final groups = <BoardGroup>[];
    byValue.forEach((v, items) => groups.add(BoardGroup(
        dimId: dim.id, value: v, label: dim.label(v), items: items)));
    return groups;
  }

  /// Every dimension that cleanly partitions these exact tiles into 4×4 (the lenses).
  List<Dimension> lensesFor(List<Entity> tiles) =>
      registry.all.where((d) => partitionBy(tiles, d) != null).toList();

  /// Build a MULTI-LENS board: 16 tiles forming a [rowDim]×[colDim] grid (one entity
  /// per cell), so the SAME tiles split cleanly by both. Returns null if the pool
  /// can't fill the grid. This is what makes same-16 regroup possible.
  Board? assembleGrid({
    List<PathFilter> filter = const [],
    required Dimension rowDim,
    required Dimension colDim,
  }) {
    final pool = _filtered(filter);
    final cols = colDim.values.keys.toList();
    if (cols.length < 4) return null;
    final useCols = ([...cols]..shuffle(_random)).take(4).toList();
    final rowVals = rowDim.values.keys.where((rv) => useCols.every(
        (cv) => pool.any((e) => e.isIn(rowDim.id, rv) && e.isIn(colDim.id, cv)))).toList();
    if (rowVals.length < 4) return null;
    final useRows = ([...rowVals]..shuffle(_random)).take(4).toList();

    final tiles = <Entity>[];
    final used = <String>{};
    for (final rv in useRows) {
      for (final cv in useCols) {
        final cands = pool
            .where((e) => e.isIn(rowDim.id, rv) && e.isIn(colDim.id, cv) && !used.contains(e.id))
            .toList()
          ..sort((a, b) => b.recognizability.compareTo(a.recognizability));
        if (cands.isEmpty) return null;
        used.add(cands.first.id);
        tiles.add(cands.first);
      }
    }
    final groups = partitionBy(tiles, rowDim)!;
    return Board(
      dimension: rowDim,
      groups: groups,
      tiles: [...tiles]..shuffle(_random),
      filter: filter,
      lenses: lensesFor(tiles),
    );
  }
}
