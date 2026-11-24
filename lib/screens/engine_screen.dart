import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/entity.dart';
import '../models/group_words.dart';
import '../providers/engine_provider.dart';
import '../services/board_assembler.dart';
import '../services/sound_service.dart';
import '../services/speaker.dart';
import '../widgets/grown_up_panel.dart';
import '../widgets/solved_group_bar.dart';
import '../widgets/tile_card.dart';
import 'web_screen.dart';

const _purple = Color(0xFF6C5CE7);
const _deepPurple = Color(0xFF4A3FB0);
const _ink = Color(0xFF2D3436);
const _groupColors = [
  Color(0xFF6C5CE7),
  Color(0xFF138A7C),
  Color(0xFFB4791A),
  Color(0xFFC24E70),
];

class EngineScreen extends StatelessWidget {
  const EngineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auto = context.select<EngineProvider, bool>((g) => g.automate);
    final grew = context.select<EngineProvider, int>((g) => g.newKnots.length);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 48,
        // Automate: the app chooses the way, which is what it is designed for. Switched off,
        // the test features show (Dig deeper on each group, Back, a new set at will).
        leadingWidth: 112,
        leading: Padding(
          padding: const EdgeInsets.only(left: 10, top: 9, bottom: 9),
          child: Tooltip(
            message: auto
                ? 'Automate is on: the app chooses the next set'
                : 'Automate is off: test features are showing',
            child: InkWell(
              key: const ValueKey('automate'),
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.read<EngineProvider>().setAutomate(!auto),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: auto ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(auto ? Icons.auto_mode_rounded : Icons.science_outlined,
                        size: 15, color: auto ? _deepPurple : Colors.white),
                    const SizedBox(width: 4),
                    Text(auto ? 'Auto' : 'Test',
                        style: GoogleFonts.inter(
                            fontSize: 12, fontWeight: FontWeight.w700, color: auto ? _deepPurple : Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            ),
          ),
        ),
        // A long press on the title opens the grown-up's panel: out of a small child's way.
        title: GestureDetector(
          key: const ValueKey('title'),
          onLongPress: () => showDialog<void>(
            context: context,
            builder: (_) => GrownUpPanel(progress: context.read<EngineProvider>().progress),
          ),
          child: Text(
            'CONNECTIONS',
            style: GoogleFonts.quicksand(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: 2,
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            key: const ValueKey('web'),
            tooltip: 'The web of what he has found',
            // a small mark when the web has grown since he last looked at it
            icon: Badge(
              isLabelVisible: grew > 0,
              backgroundColor: const Color(0xFFFFC107),
              textColor: _ink,
              label: Text('+$grew'),
              child: const Icon(Icons.hub_rounded, color: Colors.white),
            ),
            onPressed: () {
              final g = context.read<EngineProvider>();
              Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ChangeNotifierProvider<EngineProvider>.value(value: g, child: const WebScreen())));
            },
          ),
          if (!auto)
            IconButton(
              tooltip: 'New board',
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: () => context.read<EngineProvider>().newBoard(),
            ),
        ],
      ),
      body: Consumer<EngineProvider>(
        builder: (context, g, _) {
          if (g.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: [
              _breadcrumb(g),
              if (!g.atFloor) _promptBanner(g),
              Expanded(
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          for (int i = 0; i < g.solved.length; i++)
                            _solvedBanner(g, g.solved[i], i),
                          if (g.atFloor)
                            _floorCard(g)
                          else if (g.boardFinished)
                            _celebration(context, g)
                          else
                            _grid(g),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                    // "Yes! Plants", "So close": over the middle of the set, then gone. It
                    // takes no room of its own (the owner, 24 Nov 2026).
                    if (!g.boardFinished)
                      Positioned.fill(child: _Flash(text: g.message, serial: g.guessCount)),
                  ],
                ),
              ),
              if (g.explanation != null && !g.wordsSmall)
                _words(g.explanation!, const Color(0xFFE6F4EA), Icons.auto_stories_rounded, 'explanation',
                    onSmall: () => g.setWordsSmall(true)),
              if (g.clue != null && !g.boardFinished) _words(g.clue!, const Color(0xFFFFF4C2), Icons.lightbulb_rounded, 'clue'),
              if (!g.atFloor && !g.boardFinished) _controls(g),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------------- sounds

  void _tapTile(EngineProvider g, Entity e) {
    final selecting = !g.isSelected(e);
    g.toggle(e);
    if (selecting) _sayName(g, e);
  }

  /// Says a thing's name: its recorded clip if it has one, the device's voice if not.
  void _sayName(EngineProvider g, Entity e) {
    final audio = g.tileMedia(e).audio;
    if (audio != null) {
      SoundService().playAsset(audio);
    } else {
      speakText(e.label);
    }
  }

  /// Says a clue or an explanation: its recorded clip if it has one, the device's voice
  /// if not. With [after], the clip waits for the sound now playing to finish.
  void _sayWords(Spoken words, {bool after = false}) {
    final audio = words.audio;
    if (audio == null) {
      speakText(words.text);
    } else if (after) {
      SoundService().playAfter(audio);
    } else {
      SoundService().playAsset(audio);
    }
  }

  void _submit(EngineProvider g) {
    final sounds = SoundService();
    final result = g.submit();
    switch (result) {
      case SubmitResult.correct:
        sounds.playCorrect();
      case SubmitResult.roundDone:
        sounds.playVictory();
      case SubmitResult.wrong:
        sounds.playWrong();
      case SubmitResult.oneAway:
        sounds.playOneAway();
      case SubmitResult.notReady:
        break;
    }
    // A group found: say why these belong together, once the sound for "right" is over.
    if ((result == SubmitResult.correct || result == SubmitResult.roundDone) && g.explanation != null) {
      _sayWords(g.explanation!, after: true);
    }
  }

  // ---------------------------------------------------------------- top bits

  Widget _breadcrumb(EngineProvider g) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600),
                children: [
                  const TextSpan(text: 'You are here:  '),
                  for (int i = 0; i < g.pathLabels.length; i++) ...[
                    TextSpan(
                      text: g.pathLabels[i],
                      style: TextStyle(
                        fontWeight: i == g.pathLabels.length - 1
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: i == g.pathLabels.length - 1 ? _ink : null,
                      ),
                    ),
                    if (i < g.pathLabels.length - 1)
                      TextSpan(
                          text: '  ›  ',
                          style: TextStyle(color: Colors.grey.shade400)),
                  ],
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!g.atRoot && !g.automate)
            TextButton.icon(
              onPressed: g.back,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back'),
              style: TextButton.styleFrom(
                foregroundColor: _purple,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }

  /// The question of the board, with the button that reads it aloud beside it rather
  /// than on a line of its own.
  Widget _promptBanner(EngineProvider g) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEBFA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Make 4 groups of 4 — sort by:',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600),
                ),
                const SizedBox(height: 2),
                Text(
                  g.prompt,
                  style: GoogleFonts.quicksand(
                      fontWeight: FontWeight.w800, fontSize: 16, color: _deepPurple),
                ),
              ],
            ),
          ),
          // the explanation, kept small by his choice: a touch brings the words back
          if (g.explanation != null && g.wordsSmall)
            IconButton(
              key: const ValueKey('explanation-open'),
              tooltip: 'Show why these belong together',
              icon: const Icon(Icons.auto_stories_rounded, size: 22, color: Color(0xFF138A7C)),
              onPressed: () => g.setWordsSmall(false),
            ),
          IconButton(
            tooltip: 'Read it to me',
            icon: const Icon(Icons.volume_up_rounded, size: 22, color: _purple),
            onPressed: () => speakText(g.prompt),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ board

  Widget _grid(EngineProvider g) {
    final tiles = g.openTiles;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.9,
      ),
      itemBuilder: (context, i) {
        final e = tiles[i];
        return TileCard(
          key: ValueKey(e.id),
          entity: e,
          media: g.tileMedia(e),
          selected: g.isSelected(e),
          onTap: () => _tapTile(g, e),
        );
      },
    );
  }

  Widget _solvedBanner(EngineProvider g, BoardGroup group, int index) {
    return BounceInDown(
      duration: const Duration(milliseconds: 500),
      child: SolvedGroupBar(
        label: group.label,
        items: group.items,
        mediaFor: g.tileMedia,
        color: _groupColors[index % _groupColors.length],
        onSay: (e) => _sayName(g, e),
        // a test feature: when the app chooses the way, a found group is not a door
        onDescend: !g.automate && g.canDescend(group) ? () => g.descendInto(group) : null,
      ),
    );
  }

  // ------------------------------------------------------------- end states

  Widget _celebration(BuildContext context, EngineProvider g) {
    // Where he goes next is one tap away, so he never waits. Four times in five the
    // button follows the best line he has shown, once in five it leads to a set he has
    // not proven (EngineProvider._chooseNext); with nothing chosen, a parallel board.
    final next = g.nextStep;
    final detail = g.automate
        ? ''
        : g.diggable.isNotEmpty
            ? 'Dig deeper into a group, or tap the arrow.'
            : 'Here comes another board.';
    // When the app chooses the way the button only says Next: where it leads is the app's
    // business, not a choice put to the child. In test mode it says where.
    final label = g.automate
        ? 'Next'
        : next == null
            ? 'Next board'
            : next.inside
                ? 'Dig deeper: ${next.label}'
                : 'Next: ${next.label}';
    return _ShowOnScreen(
        child: BounceInDown(
      duration: const Duration(milliseconds: 600),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF4C2), Color(0xFFFFE0EE)],
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            // The stars and "You did it!" on one line.
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text('⭐',
                            style: TextStyle(
                                fontSize: 26,
                                color: i < g.stars ? null : Colors.black12)),
                      ),
                  ],
                ),
                Text('You did it!',
                    style: GoogleFonts.quicksand(
                        fontWeight: FontWeight.w800, fontSize: 22, color: _ink)),
              ],
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(detail,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade800)),
            ],
            const SizedBox(height: 10),
            // Next, and beside it a small round picture of his own web: the way into the web
            // for a child, who cannot read a button's name. It is marked when the web has grown.
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 14,
              runSpacing: 8,
              children: [
                Tooltip(
                  message: 'The web of what he has found',
                  child: InkWell(
                    key: const ValueKey('web-mini'),
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) =>
                            ChangeNotifierProvider<EngineProvider>.value(value: g, child: const WebScreen()))),
                    child: Badge(
                      isLabelVisible: g.newKnots.isNotEmpty,
                      backgroundColor: const Color(0xFFFFC107),
                      textColor: _ink,
                      label: Text('+${g.newKnots.length}'),
                      child: WebMiniature(nodes: g.web),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  key: const ValueKey('next'),
                  // after a few sets the web opens first, if it has grown, and then the game goes on
                  onPressed: () async {
                    if (g.webMomentDue) {
                      g.webMomentShown();
                      await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => ChangeNotifierProvider<EngineProvider>.value(
                              value: g, child: const WebScreen(thenNext: true))));
                    }
                    g.goNext();
                  },
                  icon: Icon(!g.automate && next != null && next.inside
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_forward_rounded),
                  label: Text(label),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ));
  }

  Widget _floorCard(EngineProvider g) {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF7EE),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Text('🌱', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 10),
          Text('The edge of what’s known here',
              style: GoogleFonts.quicksand(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: g.back,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Go back'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ bottom bits

  /// A clue or an explanation, shown for the grown-up beside him and spoken for the
  /// child. Tapping it says it again. With [onSmall] it carries a small arrow that puts it
  /// away: on a phone the words take room the set needs.
  Widget _words(Spoken words, Color tint, IconData icon, String name, {VoidCallback? onSmall}) {
    return GestureDetector(
      key: ValueKey(name),
      onTap: () => _sayWords(words),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        padding: EdgeInsets.fromLTRB(12, 8, onSmall == null ? 12 : 2, 8),
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(14)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: _deepPurple),
            const SizedBox(width: 8),
            Expanded(
              child: Text(words.text,
                  style: GoogleFonts.inter(fontSize: 14, height: 1.3, color: _ink)),
            ),
            if (onSmall != null)
              IconButton(
                key: ValueKey('$name-small'),
                tooltip: 'Keep these small',
                icon: Icon(Icons.keyboard_arrow_down_rounded, size: 24, color: Colors.grey.shade700),
                onPressed: onSmall,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 28),
              ),
          ],
        ),
      ),
    );
  }

  Widget _controls(EngineProvider g) {
    ButtonStyle outlined() => OutlinedButton.styleFrom(
          foregroundColor: Colors.black87,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );
    // Wrap (not Row): on narrow phones or with large system text the buttons flow
    // onto a second line instead of pushing Submit off-screen.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: g.selected.isEmpty ? null : g.deselectAll,
            style: outlined(),
            child: const Text('Deselect'),
          ),
          OutlinedButton(
            onPressed: g.shuffleTiles,
            style: outlined(),
            child: const Text('Shuffle'),
          ),
          // A clue leads him toward a group without naming a tile, and never costs a star.
          OutlinedButton.icon(
            key: const ValueKey('clue-button'),
            onPressed: g.hasClue
                ? () {
                    final clue = g.nextClue();
                    if (clue != null) _sayWords(clue);
                  }
                : null,
            style: outlined(),
            icon: const Icon(Icons.lightbulb_rounded, size: 18),
            label: const Text('Clue'),
          ),
          ElevatedButton(
            onPressed: g.selected.length == 4 ? () => _submit(g) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}

/// Brings its child onto the screen when it first appears. The card that ends a board
/// stands under four solved groups, and on a phone or a small tablet that is below the
/// edge of the screen: the button that leads on must not wait there for a child to find
/// it by scrolling.
class _ShowOnScreen extends StatefulWidget {
  final Widget child;
  const _ShowOnScreen({required this.child});

  @override
  State<_ShowOnScreen> createState() => _ShowOnScreenState();
}

class _ShowOnScreenState extends State<_ShowOnScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 1.0, // its foot at the foot of the list
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The answer to a guess, shown over the middle of the set: it comes in, stays a moment
/// and fades. It takes no room of its own and never stands in the way of a touch.
class _Flash extends StatefulWidget {
  const _Flash({required this.text, required this.serial});
  final String text;

  /// Changes with every guess: the same words are shown afresh.
  final int serial;

  @override
  State<_Flash> createState() => _FlashState();
}

class _FlashState extends State<_Flash> with SingleTickerProviderStateMixin {
  late final AnimationController _life =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));
  String _shown = '';

  @override
  void didUpdateWidget(_Flash old) {
    super.didUpdateWidget(old);
    if (widget.serial != old.serial && widget.text.isNotEmpty) {
      _shown = widget.text;
      _life.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _life,
        builder: (context, _) {
          final t = _life.value;
          if (_shown.isEmpty || t <= 0 || t >= 1) return const SizedBox.shrink();
          // in quickly, a moment at rest, then away
          final seen = t < 0.12 ? t / 0.12 : (t > 0.7 ? (1 - t) / 0.3 : 1.0);
          final right = _shown.startsWith('Yes');
          final close = _shown.startsWith('So close');
          final ink = right
              ? const Color(0xFF138A7C)
              : close
                  ? const Color(0xFFB4791A)
                  : const Color(0xFFC24E70);
          return Center(
            child: Opacity(
              opacity: seen.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.9 + 0.1 * (t < 0.12 ? t / 0.12 : 1.0),
                child: Container(
                  key: const ValueKey('flash'),
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: ink.withValues(alpha: 0.55), width: 2),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 16, offset: const Offset(0, 5)),
                    ],
                  ),
                  child: Text(_shown,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.quicksand(fontSize: 24, height: 1.15, fontWeight: FontWeight.w800, color: ink)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
