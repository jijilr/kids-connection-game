import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import '../models/entity.dart';
import '../models/dimension.dart';
import 'board_assembler.dart';
import 'media.dart';

/// Loads a domain's cached graph (entities + dimensions) from bundled JSON, plus which
/// photos / emoji / voice clips exist, and hands back a ready assembler. (Runtime
/// DeepSeek generation is a later phase; for now content is baked in — BUILD_PLAN.)
class ContentRepository {
  late List<Entity> entities;
  late DimensionRegistry registry;
  late BoardAssembler assembler;
  MediaResolver media = const MediaResolver.empty();
  bool _loaded = false;

  ContentRepository();

  /// For tests: use in-memory data instead of the asset bundle.
  ContentRepository.fromData(List<Entity> ents, DimensionRegistry reg,
      {Random? random, MediaResolver media = const MediaResolver.empty()}) {
    _set(ents, reg, media, random);
  }

  void _set(List<Entity> ents, DimensionRegistry reg, MediaResolver m, Random? random) {
    entities = ents;
    registry = reg;
    media = m;
    // Favour animals that have a picture so a board never gives a group away by
    // mixing picture tiles with bare-text tiles.
    assembler = BoardAssembler(ents, reg, random: random, preferred: m.hasPicture);
    _loaded = true;
  }

  Future<void> load({String domain = 'animals'}) async {
    if (_loaded) return;
    final entRaw = await rootBundle.loadString('Assets/data/$domain/entities.json');
    final dimRaw = await rootBundle.loadString('Assets/data/$domain/dimensions.json');
    final ents = ((json.decode(entRaw) as Map)['entities'] as List)
        .map((e) => Entity.fromJson(e as Map<String, dynamic>))
        .toList();
    final reg = DimensionRegistry.fromJson(json.decode(dimRaw) as Map<String, dynamic>);
    _set(ents, reg, await MediaResolver.load(), null);
  }
}
