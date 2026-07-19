// Standalone sanity check for the board assembler — runs without Flutter.
//   dart run tools/check_assembler.dart
import 'dart:convert';
import 'dart:io';
import 'package:connections_game/models/entity.dart';
import 'package:connections_game/models/dimension.dart';
import 'package:connections_game/services/board_assembler.dart';

void main() {
  final entJson =
      jsonDecode(File('Assets/data/animals/entities.json').readAsStringSync());
  final dimJson =
      jsonDecode(File('Assets/data/animals/dimensions.json').readAsStringSync());
  final entities = (entJson['entities'] as List)
      .map((e) => Entity.fromJson(e as Map<String, dynamic>))
      .toList();
  final registry = DimensionRegistry.fromJson(dimJson as Map<String, dynamic>);
  final asm = BoardAssembler(entities, registry);

  print('entities: ${entities.length} | '
      'dimensions: ${registry.all.map((d) => d.id).toList()} | '
      'boardable (arity>=4): ${registry.boardable.map((d) => d.id).toList()}');

  final board = asm.assemble(dimension: registry.byId('category')!);
  if (board == null) {
    stderr.writeln('FAIL: could not assemble root category board');
    exit(1);
  }
  print('\nROOT BOARD — "${board.dimension.question}"');
  for (final g in board.groups) {
    print('  ${g.label}: ${g.items.map((e) => e.name).join(", ")}');
  }
  final ids = board.tiles.map((e) => e.id).toSet();
  if (board.tiles.length != 16 || ids.length != 16 || board.groups.length != 4) {
    stderr.writeln('FAIL: board is not 16 distinct tiles in 4 groups');
    exit(1);
  }
  print('  -> 16 distinct tiles, 4 groups of 4  [OK]');

  final first = board.groups.first;
  final dims = asm.boardableDimensions([(first.dimId, first.value)]);
  print('\nDESCEND into "${first.label}" — boardable dimensions inside it: '
      '${dims.map((d) => d.id).toList()}');
  print('(empty is expected & correct: a single category rarely has a 4-valued '
      'sub-dimension — the wide-shallow floor. Compound dimensions come in P4.)');
  print('\nALL OK');
}
