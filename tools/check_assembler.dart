// Standalone sanity check for the board assembler — runs without Flutter.
//   dart run tools/check_assembler.dart
import 'dart:convert';
import 'dart:io';
import 'package:connections_game/models/entity.dart';
import 'package:connections_game/models/dimension.dart';
import 'package:connections_game/services/board_assembler.dart';

Map<String, dynamic> readData(String file) =>
    jsonDecode(File('Assets/data/$file').readAsStringSync()) as Map<String, dynamic>;

void main() {
  final entities = (readData('things.json')['things'] as Map<String, dynamic>)
      .entries
      .map((e) => Entity.fromJson(e.key, e.value as Map<String, dynamic>))
      .toList();
  final registry = DimensionRegistry.fromJson(readData('dictionary.json'));
  final start = readData('settings.json')['start'] as Map<String, dynamic>;
  final asm = BoardAssembler(entities, registry);

  print('things: ${entities.length} | '
      'fields: ${registry.all.map((d) => d.id).toList()} | '
      'could fill a board (>= 4 values): ${registry.boardable.map((d) => d.id).toList()}');

  final board = asm.assemble(dimension: registry.byId(start['field'] as String)!);
  if (board == null) {
    stderr.writeln('FAIL: could not assemble the starting board');
    exit(1);
  }
  print('\nSTARTING BOARD — "${board.dimension.question}"');
  for (final g in board.groups) {
    print('  ${g.label}: ${g.items.map((e) => e.label).join(", ")}');
  }
  final ids = board.tiles.map((e) => e.id).toSet();
  if (board.tiles.length != 16 || ids.length != 16 || board.groups.length != 4) {
    stderr.writeln('FAIL: board is not 16 distinct tiles in 4 groups');
    exit(1);
  }
  print('  -> 16 distinct tiles, 4 groups of 4  [OK]');

  print('\nDIG DEEPER — fields that fill a board inside each group:');
  for (final g in board.groups) {
    final dims = asm.boardableDimensions([(g.dimId, g.value)]);
    print('  ${g.label}: ${dims.map((d) => d.id).toList()}');
  }
  print('(empty is expected where a group has no field with four full values yet.)');

  print('\nALL OK');
}
