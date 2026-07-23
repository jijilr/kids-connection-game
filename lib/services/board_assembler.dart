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

  /// "Regroup" lenses for a node: boardable dimensions (excluding [exceptId]) that
  /// cover a majority of the filtered pool — i.e. re-sort roughly the *same* animals
  /// a different way, rather than silently dropping most of them.
  List<Dimension> regroupDimensions(List<PathFilter> filter, String exceptId) {
    final pool = _filtered(filter);
    if (pool.isEmpty) return const [];
    final out = <Dimension>[];
    for (final d in boardableDimensions(filter)) {
      if (d.id == exceptId) continue;
      final covered = pool.where((e) {
        final v = e.valueFor(d.id);
        return v != null && d.values.containsKey(v);
      }).length;
      if (covered >= pool.length * 0.6) out.add(d);
    }
    return out;
  }
}
