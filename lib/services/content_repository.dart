import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/entity.dart';
import '../models/dimension.dart';
import 'board_assembler.dart';

/// Loads a domain's cached graph (entities + dimensions) from bundled JSON and
/// hands back a ready assembler. (Runtime/DeepSeek generation is a later phase;
/// for now the content is baked in — BUILD_PLAN.)
class ContentRepository {
  late final List<Entity> entities;
  late final DimensionRegistry registry;
  late final BoardAssembler assembler;

  Future<void> load({String domain = 'animals'}) async {
    final entRaw =
        await rootBundle.loadString('Assets/data/$domain/entities.json');
    final dimRaw =
        await rootBundle.loadString('Assets/data/$domain/dimensions.json');
    entities = ((json.decode(entRaw) as Map)['entities'] as List)
        .map((e) => Entity.fromJson(e as Map<String, dynamic>))
        .toList();
    registry =
        DimensionRegistry.fromJson(json.decode(dimRaw) as Map<String, dynamic>);
    assembler = BoardAssembler(entities, registry);
  }
}
