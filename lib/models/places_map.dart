import '../services/board_assembler.dart' show PathFilter;

/// One kind of a question at a place: whether it can be shown now, and the place it is.
class KindAt {
  final String place;
  final bool ready;
  final int things;
  const KindAt({required this.place, required this.ready, required this.things});
}

/// One question asked at a place.
class Asked {
  final String question;

  /// It can fill a set there now (in pictures, where the settings ask for pictures).
  final bool makesASet;
  final Map<String, KindAt> kinds;

  /// The place of the things that have no single answer to it, and whether four of them
  /// can be shown as the group "in between".
  final String? inBetweenPlace;
  final bool inBetweenReady;

  /// The kinds its "in between" things lie between: it is shown only when he knows them.
  final List<String> inBetweenSides;

  const Asked({
    required this.question,
    required this.makesASet,
    required this.kinds,
    this.inBetweenPlace,
    this.inBetweenReady = false,
    this.inBetweenSides = const [],
  });
}

/// One place of the game: where circles overlap.
class Place {
  /// Its name: the answers that define it, in the dictionary's order (`animal/bird`).
  /// The first place is `seed`.
  final String id;
  final String name;

  /// The circles it lies in, as (question, answer), in the dictionary's order.
  final List<PathFilter> circles;

  /// The places one circle wider, each with the answer this place adds to it.
  final Map<String, PathFilter> liesIn;

  /// Of those, the places where a set leads here: the roads to it.
  final List<String> reachedFrom;

  /// The questions asked here, the one the place has always had first.
  final List<Asked> asks;

  /// ready, can be made, held, end, or a group only; and the reason where it is not ready.
  final String state;
  final String why;

  /// The file that holds the things a set here needs (`places/animal__bird.json`), for a
  /// place that can make a set. The game loads it when it goes there.
  final String? thingsFile;

  /// The thing whose picture stands for the place on his web.
  final String? picture;

  /// For a group "in between": the places it lies between.
  final List<String> between;

  const Place({
    required this.id,
    required this.name,
    required this.circles,
    this.liesIn = const {},
    this.reachedFrom = const [],
    this.asks = const [],
    this.state = 'a group only',
    this.why = '',
    this.thingsFile,
    this.picture,
    this.between = const [],
  });

  /// A set can be made here now.
  bool get ready => asks.any((a) => a.makesASet);

  /// Nothing lies below it: the end of a branch.
  bool get isEnd => state == 'end';
}

/// The map of every place (the owner, 24 Nov 2026: "some kind of json with meta data of
/// each node... that is the nerve system of the whole thing").
///
/// It is built by one program, tools/catalogue/places.py, from the things, the
/// dictionary and the decisions on record, into `Assets/data/places.json`. The game
/// reads it and works out nothing about places for itself: which places there are, what
/// each is called, what is asked there, which kinds can be shown, where each kind leads,
/// and what lies in what. What the game still does by itself is what must happen while
/// he plays: choosing sixteen things, and seeing that they have one clean solution.
class PlacesMap {
  final Map<String, Place> _places;

  /// How many things the map was built for: a map and a list of things that do not match
  /// were read at different moments, and are not used together.
  final int things;

  /// The mark of the moment the map was built. Every place's file of things carries the
  /// same mark; a file with another mark was written at another moment and is not used.
  final String stamp;

  final Map<String, String> _byCircles;

  PlacesMap(this._places, {this.things = 0, this.stamp = ''})
      : _byCircles = {for (final p in _places.values) _key(p.circles): p.id};

  PlacesMap.empty()
      : _places = const {},
        things = 0,
        stamp = '',
        _byCircles = const {};

  /// The things are stored by place: the first place has a file of its own.
  bool get byPlace => _places['seed']?.thingsFile != null;

  static String _key(List<PathFilter> circles) =>
      (circles.map((c) => '${c.$1}=${c.$2}').toList()..sort()).join('&');

  bool get isEmpty => _places.isEmpty;
  Iterable<Place> get all => _places.values;
  Place? operator [](String id) => _places[id];

  /// The place where these circles overlap, whatever order they are given in.
  Place? at(List<PathFilter> circles) => _places[_byCircles[_key(circles)]];

  /// The name of the place where these circles overlap. A place that is not on the map
  /// is named by its answers in the order given.
  String idOf(List<PathFilter> circles) =>
      _byCircles[_key(circles)] ?? (circles.isEmpty ? 'seed' : circles.map((c) => c.$2).join('/'));

  /// The circles in the order the map keeps them: the dictionary's, whatever the road.
  List<PathFilter> canon(List<PathFilter> circles) => at(circles)?.circles ?? circles;

  /// Every place below the first that can make a set now, nearest first.
  List<Place> get ready => [
        for (final p in _places.values)
          if (p.id != 'seed' && p.ready) p
      ];

  factory PlacesMap.fromJson(Map<String, dynamic> json) {
    PathFilter step(Object? s) => ('${(s as List)[0]}', '${s[1]}');
    final places = <String, Place>{};
    ((json['places'] as Map?) ?? const {}).forEach((id, value) {
      final p = value as Map;
      places['$id'] = Place(
        id: '$id',
        name: '${p['name'] ?? id}',
        circles: [for (final s in (p['circles'] as List? ?? const [])) step(s)],
        liesIn: {
          for (final e in ((p['lies_in'] as Map?) ?? const {}).entries) '${e.key}': step(e.value)
        },
        reachedFrom: [for (final r in (p['reached_from'] as List? ?? const [])) '$r'],
        asks: [
          for (final a in (p['asks'] as List? ?? const []).cast<Map>())
            Asked(
              question: '${a['question']}',
              makesASet: a['makes_a_set'] == true,
              inBetweenPlace: a['in_between_place'] as String?,
              inBetweenReady: a['in_between_ready'] == true,
              inBetweenSides: [for (final s in (a['in_between_sides'] as List? ?? const [])) '$s'],
              kinds: {
                for (final k in ((a['kinds'] as Map?) ?? const {}).entries)
                  '${k.key}': KindAt(
                    place: '${(k.value as Map)['place']}',
                    ready: (k.value as Map)['ready'] == true,
                    things: ((k.value as Map)['things'] as num?)?.toInt() ?? 0,
                  )
              },
            )
        ],
        state: '${p['state'] ?? ''}',
        why: '${p['why'] ?? ''}',
        thingsFile: p['things_file'] as String?,
        picture: p['picture'] as String?,
        between: [for (final b in (p['between'] as List? ?? const [])) '$b'],
      );
    });
    return PlacesMap(places,
        things: (json['things'] as num?)?.toInt() ?? 0, stamp: '${json['stamp'] ?? ''}');
  }
}
