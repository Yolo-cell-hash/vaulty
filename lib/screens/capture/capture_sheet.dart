import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/memory.dart';
import '../../services/ocr_service.dart';
import '../../services/personalization.dart';
import '../../services/settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/glyphs.dart';
import '../memory_editor_screen.dart';
import 'draft.dart';
import 'quick_capture_screen.dart';
import 'scan_screen.dart';

Future<void> showCaptureSheet(BuildContext context) {
  return showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const _CaptureSheet());
}

class _CaptureSheet extends ConsumerWidget {
  const _CaptureSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Templates for what they said they care about come first.
    final templates = templatesFor(ref.watch(settingsProvider.select((s) => s.goals)));
    final nav = Navigator.of(context);

    Future<void> scan(ImageSource source) async {
      final file = await OcrService.pickImage(source);
      nav.pop();
      if (file == null) return;
      nav.push(MaterialPageRoute(builder: (_) => ScanScreen(image: file)));
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New memory', style: context.type.headline),
            const SizedBox(height: 4),
            Text('Type it, snap it, or start from a template.', style: context.type.bodySoft),
            const SizedBox(height: 20),
            ListGroup(
              children: [
                ListRow(
                  title: 'Type it',
                  subtitle: 'Say it naturally. Dates and details get picked up.',
                  glyph: G.pen,
                  onTap: () {
                    nav.pop();
                    nav.push(MaterialPageRoute(builder: (_) => const QuickCaptureScreen()));
                  },
                ),
                ListRow(
                  title: 'Scan a document',
                  subtitle: 'Passports, cards, labels. Read on-device.',
                  glyph: G.scan,
                  onTap: () => scan(ImageSource.camera),
                ),
                ListRow(
                  title: 'From your photos',
                  subtitle: 'Screenshots and receipts work too.',
                  glyph: G.image,
                  onTap: () => scan(ImageSource.gallery),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Eyebrow('Templates'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in templates)
                  VChip(
                    label: t.label,
                    icon: t.recurrence == Recurrence.yearly ? G.cake : t.category.glyph,
                    onTap: () {
                      nav.pop();
                      nav.push(
                        MaterialPageRoute(
                          builder: (_) => MemoryEditorScreen(
                            initial: blankMemory(
                              title: t.label,
                              category: t.category,
                              keys: t.keys,
                              sensitive: t.sensitive,
                              recurrence: t.recurrence,
                            ),
                            isNew: true,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
