import 'dart:convert';
import 'dart:io';

import 'package:connections_game/models/places_map.dart';

/// The map of places for a test. The rules of what a place is are written once, in
/// tools/catalogue/places.py (the owner, 24 Nov 2026: the map is "the nerve system of the
/// whole thing"). So a test never works a map out for itself: it reads the real one, or
/// asks the builder for the map of its own made-up game.

/// The map of the real game, as it stands in Assets/data/places.json.
PlacesMap realPlaces() =>
    PlacesMap.fromJson(jsonDecode(File('Assets/data/places.json').readAsStringSync()) as Map<String, dynamic>);

/// The map of a made-up game, built by the one builder. [dictionary] and [things] are
/// shaped as `dictionary.json` and the `things` of `things.json`.
PlacesMap placesFor({
  required Map<String, dynamic> dictionary,
  required Map<String, dynamic> things,
  required String startField,
  String startLabel = 'Everything',
}) {
  final folder = Directory.systemTemp.createTempSync('places_for_a_test');
  try {
    final world = File('${folder.path}/world.json')
      ..writeAsStringSync(jsonEncode({
        'dictionary': dictionary,
        'things': things,
        'settings': {
          'start': {'field': startField, 'label': startLabel},
          'boards_need_pictures': false,
        },
      }));
    final run = Process.runSync('python', ['tools/catalogue/places.py', 'for', world.path],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    if (run.exitCode != 0) {
      throw StateError('The builder of the map failed: ${run.stderr}');
    }
    return PlacesMap.fromJson(jsonDecode(run.stdout as String) as Map<String, dynamic>);
  } finally {
    folder.deleteSync(recursive: true);
  }
}
