import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/file_saver.dart';
import '../services/progress.dart';

/// For the grown-up, opened by a long press on the game's title so that a small
/// child does not land on it. It shows where the child has been, and saves that as a
/// file for the job that prepares the next level. Nothing here leaves the device
/// unless the grown-up saves or copies it.
class GrownUpPanel extends StatelessWidget {
  final Progress progress;
  final bool Function(String name, String text) saveFile;

  const GrownUpPanel({super.key, required this.progress, this.saveFile = saveTextFile});

  static const fileName = 'progress.json';

  @override
  Widget build(BuildContext context) {
    final boards = progress.boards.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return AlertDialog(
      title: Text('For the grown-up',
          style: GoogleFonts.quicksand(fontWeight: FontWeight.w800, fontSize: 20)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              boards.isEmpty
                  ? 'No board has been played on this device yet.'
                  : 'Boards played on this device. Only boards are recorded, nothing about the child.',
              style: GoogleFonts.inter(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final e in boards)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '${e.key}: opened ${e.value.opened}, solved ${e.value.solved}',
                        key: ValueKey('progress-${e.key}'),
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Save the file into the project as tools/job/$fileName. The job then prepares one step ahead of where he is.',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('progress-copy'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: progress.toFileText()));
            if (context.mounted) _say(context, 'Copied. Paste it into tools/job/$fileName.');
          },
          child: const Text('Copy'),
        ),
        TextButton(
          key: const ValueKey('progress-save'),
          onPressed: () {
            final saved = saveFile(fileName, progress.toFileText());
            _say(context, saved ? 'Saved as $fileName.' : 'This device cannot save a file here. Use Copy.');
          },
          child: const Text('Save file'),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }

  void _say(BuildContext context, String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
