import 'dart:convert';

import 'package:http/http.dart' as http;

import 'progress.dart';

/// What the helper on the owner's PC says about the game's data right now.
class LiveState {
  /// Changes whenever the data has changed: a set was made while he played.
  final String version;

  /// Every picture and sound there is now, as the game names them.
  final Set<String> files;

  /// Lines that can never be made into a set; the game lets them go.
  final List<String> dead;

  const LiveState({required this.version, required this.files, this.dead = const []});

  static LiveState? fromJson(Object? json) {
    if (json is! Map || json['version'] is! String || json['files'] is! List) return null;
    return LiveState(
      version: json['version'] as String,
      files: {for (final f in json['files'] as List) if (f is String) f},
      dead: [for (final d in (json['dead'] is List ? json['dead'] as List : const [])) if (d is String) d],
    );
  }
}

/// The game's link to the helper on the owner's PC (tools/live/helper.py), which keeps
/// sets ready ahead of the child (the owner's design of 24 Nov 2026: one game, dynamic
/// data). Through it the game reads its data as it stands now, and tells the helper
/// which lines he is following. Where there is no helper (the plain web site, a phone
/// with no network) every call answers "nothing", and the game plays from what it ships
/// with.
abstract class LiveLink {
  Future<LiveState?> state();

  /// Tell the helper where he is. Answers the lines that can never be made.
  Future<List<String>> send(Progress progress);

  /// The text of one of the game's data files as it stands now, or null.
  Future<String?> read(String asset);
}

class HttpLiveLink implements LiveLink {
  HttpLiveLink({Uri? base, http.Client? client})
      : _base = base ?? Uri.base,
        _client = client ?? http.Client();

  final Uri _base;
  final http.Client _client;
  static const _wait = Duration(seconds: 6);

  @override
  Future<LiveState?> state() async {
    try {
      final reply = await _client.get(_base.resolve('live/state')).timeout(_wait);
      if (reply.statusCode != 200) return null;
      return LiveState.fromJson(jsonDecode(utf8.decode(reply.bodyBytes)));
    } catch (_) {
      return null; // no helper here: the game plays from what it ships with
    }
  }

  @override
  Future<List<String>> send(Progress progress) async {
    try {
      final reply = await _client
          .post(_base.resolve('live/progress'),
              headers: const {'Content-Type': 'application/json'}, body: jsonEncode(progress.toJson()))
          .timeout(_wait);
      if (reply.statusCode != 200) return const [];
      final answer = jsonDecode(utf8.decode(reply.bodyBytes));
      final dead = answer is Map ? answer['dead'] : null;
      return [for (final d in (dead is List ? dead : const [])) if (d is String) d];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<String?> read(String asset) async {
    try {
      final reply = await _client.get(_base.resolve('assets/$asset')).timeout(_wait);
      return reply.statusCode == 200 ? utf8.decode(reply.bodyBytes) : null;
    } catch (_) {
      return null;
    }
  }
}
