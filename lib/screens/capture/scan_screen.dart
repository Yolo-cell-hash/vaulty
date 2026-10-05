import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/memory.dart';
import '../../services/attachment_store.dart';
import '../../services/ocr_service.dart';
import '../../services/smart_parser.dart';
import '../../state/vault_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/flow_sheet.dart';
import '../../widgets/glyphs.dart';
import '../memory_editor_screen.dart';
import 'draft.dart';

/// Runs on-device OCR on a captured photo, then opens the editor pre-filled.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key, required this.image});

  final File image;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  Uint8List? _preview;
  int _stage = 0;
  String? _error;

  static const _stages = ['Reading text on this phone', 'Finding dates', 'Picking out details', 'Encrypting the photo'];

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _advance(int s) async {
    if (!mounted) return;
    setState(() => _stage = s);
    HapticFeedback.selectionClick();
    await Future<void>.delayed(const Duration(milliseconds: 240));
  }

  Future<void> _run() async {
    try {
      final bytes = await widget.image.readAsBytes();
      if (mounted) setState(() => _preview = bytes);
      final known = ref.read(tagsProvider).value ?? const <Tag>[];
      final text = await OcrService.recognize(widget.image);
      await _advance(1);
      final parsed = text.trim().isEmpty
          ? const ParsedCapture(title: 'Scanned item', category: MemoryCategory.other, fields: [], rawText: '')
          : deviceParser(known: known).parseOcr(text);
      await _advance(2);
      await _advance(3);
      final attachment = await AttachmentStore.importFile(widget.image);
      await _advance(4);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MemoryEditorScreen(
            initial: memoryFromParsed(parsed, attachments: [attachment], known: known),
            isNew: true,
            notice: text.trim().isEmpty ? 'No text found in that photo. Add the details yourself.' : null,
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return Scaffold(
      appBar: AppBar(
        // On iOS this is the first page of a sheet, which closes rather than goes back.
        leading: context.isCupertino
            ? VIconButton(G.close, label: 'Close', onTap: () => closeFlow(context))
            : VIconButton(G.chevronLeft, label: 'Back', onTap: () => closeFlow(context)),
        title: const Text('Scan'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_preview != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.l),
                  child: SizedBox(
                    height: 220,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(_preview!, fit: BoxFit.cover),
                        ColoredBox(color: Colors.black.withValues(alpha: .25)),
                        if (_error == null && _stage < _stages.length) const _ScanLine(),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 28),
              if (_error != null) ...[
                Text('Couldn’t read that one', style: context.type.headline),
                const SizedBox(height: 8),
                Text('Try again in better light, or type it in instead.', style: context.type.bodySoft),
                const SizedBox(height: 8),
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Technical details', style: context.type.caption),
                    children: [SelectableText(_error!, maxLines: 6, style: context.type.mono(11, c.danger))],
                  ),
                ),
                const Spacer(),
                VButton(label: 'Go back', onPressed: () => closeFlow(context)),
              ] else ...[
                Text('Reading your photo', style: context.type.headline),
                const SizedBox(height: 20),
                for (var i = 0; i < _stages.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 22,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: i < _stage
                                ? VIcon(G.check, key: const ValueKey('done'), size: 20, color: c.ok, stroke: 2.2)
                                : i == _stage
                                ? Spinner(key: const ValueKey('run'), size: 22, color: c.ink)
                                : Container(
                                    key: const ValueKey('wait'),
                                    margin: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(color: c.line, shape: BoxShape.circle),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          _stages[i],
                          style: context.type.body.copyWith(
                            color: i <= _stage ? c.ink : c.inkFaint,
                            fontWeight: i == _stage ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanLine extends StatefulWidget {
  const _ScanLine();

  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final acid = context.vc.acid;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Align(
        alignment: Alignment(0, _c.value * 2 - 1),
        child: Container(
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: acid,
            boxShadow: [BoxShadow(color: acid.withValues(alpha: .6), blurRadius: 14, spreadRadius: 1)],
          ),
        ),
      ),
    );
  }
}
