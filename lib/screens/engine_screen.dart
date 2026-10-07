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
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      for (int i = 0; i < g.solved.length; i++)
                        _solvedBanner(g, g.solved[i], i),
                      if (g.atFloor)
                        _floorCard(g)
                      else if (g.boardFinished)
                        _celebration(g)
                      else
                        _grid(g),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              if (g.explanation != null) _words(g.explanation!, const Color(0xFFE6F4EA), Icons.auto_stories_rounded, 'explanation'),
              if (g.clue != null && !g.boardFinished) _words(g.clue!, const Color(0xFFFFF4C2), Icons.lightbulb_rounded, 'clue'),
              if (g.message.isNotEmpty && !g.boardFinished) _status(g),
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
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
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
          if (!g.atRoot)
            TextButton.icon(
              onPressed: g.back,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back'),
              style: TextButton.styleFrom(foregroundColor: _purple),
            ),
        ],
      ),
    );
  }

  Widget _promptBanner(EngineProvider g) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEBFA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Make 4 groups of 4 — sort by:',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600),
                ),
              ),
              IconButton(
                tooltip: 'Read it to me',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.volume_up_rounded, size: 20, color: _purple),
                onPressed: () => speakText(g.prompt),
              ),
            ],
          ),
          Text(
            g.prompt,
            style: GoogleFonts.quicksand(
                fontWeight: FontWeight.w800, fontSize: 16, color: _deepPurple),
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
        onDescend: g.canDescend(group) ? () => g.descendInto(group) : null,
      ),
    );
  }

  // ------------------------------------------------------------- end states

  Widget _celebration(EngineProvider g) {
    // Where he goes next is one tap away, so he never waits. If a group can be dug into,
    // the button leans toward the branch he has visited least; if none can, it opens a
    // parallel board at the same depth.
    final lean = g.suggestedDig;
    final detail = lean != null
        ? 'Dig deeper into a group, or tap the arrow for the one you know least.'
        : 'Here comes another board.';
    return BounceInDown(
      duration: const Duration(milliseconds: 600),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(18),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Text('⭐',
                        style: TextStyle(
                            fontSize: 32,
                            color: i < g.stars ? null : Colors.black12)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('You did it!',
                style: GoogleFonts.quicksand(
                    fontWeight: FontWeight.w800, fontSize: 22, color: _ink)),
            const SizedBox(height: 6),
            Text(detail,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade800)),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              key: const ValueKey('next'),
              onPressed: lean != null ? () => g.descendInto(lean) : g.nextBoard,
              icon: Icon(lean != null ? Icons.arrow_downward_rounded : Icons.arrow_forward_rounded),
              label: Text(lean != null ? 'Dig deeper: ${lean.label}' : 'Next board'),
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
      ),
    );
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

  Widget _status(EngineProvider g) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        g.message,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
            fontSize: 14, fontWeight: FontWeight.w700, color: Colors.grey.shade800),
      ),
    );
  }

  /// A clue or an explanation, shown for the grown-up beside him and spoken for the
  /// child. Tapping it says it again.
  Widget _words(Spoken words, Color tint, IconData icon, String name) {
    return GestureDetector(
      key: ValueKey(name),
      onTap: () => _sayWords(words),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
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
