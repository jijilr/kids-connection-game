import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import '../models/entity.dart';

/// What we can show and play for one animal. Any field may be null.
class EntityMedia {
  final String? image; // bundled photo, e.g. Assets/lion_1.png
  final String? emoji; // fallback picture when there is no photo
  final String? audio; // recorded name clip, e.g. Assets/audio/names/name_lion.mp3
  const EntityMedia({this.image, this.emoji, this.audio});

  bool get hasPicture => image != null || emoji != null;
}

/// Resolves photos, emoji and recorded voice clips for entities. Uses the real asset
/// manifest, so it only ever points at files that actually ship with the app.
class MediaResolver {
  final Set<String> _assets;
  const MediaResolver(this._assets);

  const MediaResolver.empty() : _assets = const {};

  static Future<MediaResolver> load() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return MediaResolver(manifest.listAssets().toSet());
    } catch (_) {
      return const MediaResolver.empty();
    }
  }

  /// Generated ids whose old picture / clip was saved under a different name.
  static const _alias = {
    'tyrannosaurus_rex': 'trex',
    'pterodactylus': 'pterodactyl',
  };

  /// Emoji stand-ins for animals without a photo. Only emoji that genuinely show the
  /// animal — e.g. no lizard emoji for salamanders, which would teach the wrong thing.
  static const _emoji = {
    'dog': '🐕', 'cat': '🐈', 'elephant': '🐘', 'horse': '🐎', 'cow': '🐄',
    'pig': '🐖', 'lion': '🦁', 'tiger': '🐅', 'bear': '🐻', 'whale': '🐋',
    'dolphin': '🐬', 'bat': '🦇',
    'eagle': '🦅', 'penguin': '🐧', 'parrot': '🦜', 'owl': '🦉', 'duck': '🦆',
    'chicken': '🐔', 'flamingo': '🦩', 'swan': '🦢', 'robin': '🐦',
    'goldfish': '🐟', 'clownfish': '🐠', 'shark': '🦈', 'salmon': '🐟',
    'pufferfish': '🐡', 'angelfish': '🐠', 'catfish': '🐟', 'trout': '🐟',
    'butterfly': '🦋', 'bee': '🐝', 'ant': '🐜', 'ladybug': '🐞',
    'grasshopper': '🦗', 'cricket': '🦗',
    'snake': '🐍', 'turtle': '🐢', 'lizard': '🦎', 'crocodile': '🐊',
    'alligator': '🐊', 'chameleon': '🦎', 'iguana': '🦎', 'gecko': '🦎',
    'frog': '🐸', 'toad': '🐸',
    'tyrannosaurus_rex': '🦖', 'spinosaurus': '🦖', 'velociraptor': '🦖',
    'allosaurus': '🦖', 'giganotosaurus': '🦖',
    'diplodocus': '🦕', 'brachiosaurus': '🦕',
  };

  EntityMedia forEntity(Entity e) {
    final key = _alias[e.id] ?? e.id;
    final img = 'Assets/${key}_1.png';
    final aud = 'Assets/audio/names/name_$key.mp3';
    return EntityMedia(
      image: _assets.contains(img) ? img : null,
      emoji: _emoji[e.id],
      audio: _assets.contains(aud) ? aud : null,
    );
  }

  bool hasPicture(Entity e) => forEntity(e).hasPicture;
}
