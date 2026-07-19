import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/engine_provider.dart';
import '../services/board_assembler.dart';
import '../widgets/tile_card.dart';

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
        title: Text(
          'CONNECTIONS',
          style: GoogleFonts.quicksand(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: 2,
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
              _breadcrumb(context, g),
              if (!g.atFloor) _lensBanner(g),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      for (int i = 0; i < g.solved.length; i++)
                        _solvedBanner(context, g, g.solved[i], i),
                      if (g.solved.isNotEmpty) const SizedBox(height: 6),
                      if (g.atFloor)
                        _floorCard(context)
                      else
                        _grid(context, g),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              _status(g),
              _controls(context, g),
            ],
          );
        },
      ),
    );
  }

  Widget _breadcrumb(BuildContext context, EngineProvider g) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'You are here:  '),
                  for (int i = 0; i < g.pathLabels.length; i++) ...[
                    TextSpan(
                      text: g.pathLabels[i],
                      style: TextStyle(
                        fontWeight: i == g.pathLabels.length - 1
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: i == g.pathLabels.length - 1
                            ? const Color(0xFF2D3436)
                            : Colors.grey.shade600,
                      ),
                    ),
                    if (i < g.pathLabels.length - 1)
                      TextSpan(
                        text: '  ›  ',
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                  ],
                ],
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!g.atRoot)
            TextButton.icon(
              onPressed: () => g.back(),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back'),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFF6C5CE7)),
            ),
        ],
      ),
    );
  }

  Widget _lensBanner(EngineProvider g) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEBFA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 18, color: Color(0xFF6C5CE7)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              g.board!.dimension.question,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: const Color(0xFF4A3FB0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context, EngineProvider g) {
    final tiles = g.openTiles;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemBuilder: (context, i) {
        final e = tiles[i];
        return TileCard(
          entity: e,
          selected: g.selected.any((x) => x.id == e.id),
          onTap: () => g.toggle(e),
        );
      },
    );
  }

  Widget _solvedBanner(
      BuildContext context, EngineProvider g, BoardGroup group, int index) {
    final color = _groupColors[index % _groupColors.length];
    final canDescend = g.boardComplete;
    return GestureDetector(
      onTap: canDescend ? () => g.descendInto(group) : null,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.label.toUpperCase(),
                    style: GoogleFonts.quicksand(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    group.items.map((e) => e.name).join('  ·  '),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.92),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (canDescend)
              const Row(
                children: [
                  Text('dig deeper',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                  SizedBox(width: 4),
                  Icon(Icons.south_east_rounded, color: Colors.white, size: 16),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _floorCard(BuildContext context) {
    final g = context.read<EngineProvider>();
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
          Text(
            'The edge of what\'s known here',
            style: GoogleFonts.quicksand(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'This branch has no deeper split yet. (Compound dimensions and generated content come next.)',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => g.back(),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Go back'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C5CE7),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _status(EngineProvider g) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        g.message,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: g.boardComplete ? const Color(0xFF138A7C) : Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, EngineProvider g) {
    if (g.atFloor) return const SizedBox(height: 12);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Mistakes:', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(width: 8),
              ...List.generate(EngineProvider.maxMistakes, (i) {
                final used = i < g.mistakes;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: CircleAvatar(
                    radius: 5,
                    backgroundColor: used ? const Color(0xFFC24E70) : Colors.grey.shade300,
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: g.selected.isEmpty ? null : () => g.deselectAll(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('Deselect'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => g.newBoard(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('New board'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: g.selected.length == 4 ? () => g.submit() : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C5CE7),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('Submit'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
