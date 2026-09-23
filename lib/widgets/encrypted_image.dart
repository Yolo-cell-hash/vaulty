import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/memory.dart';
import '../services/attachment_store.dart';
import '../theme/app_theme.dart';
import 'glyphs.dart';

/// Decrypts an attachment in memory and shows it. Nothing touches disk.
class EncryptedImage extends StatefulWidget {
  const EncryptedImage({super.key, required this.attachment, this.fit = BoxFit.cover});

  final Attachment attachment;
  final BoxFit fit;

  @override
  State<EncryptedImage> createState() => _EncryptedImageState();
}

class _EncryptedImageState extends State<EncryptedImage> {
  late Future<Uint8List> _bytes = AttachmentStore.read(widget.attachment);

  @override
  void didUpdateWidget(EncryptedImage old) {
    super.didUpdateWidget(old);
    if (old.attachment.filePath != widget.attachment.filePath) {
      _bytes = AttachmentStore.read(widget.attachment);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.hasData) {
          return Image.memory(snap.data!, fit: widget.fit, gaplessPlayback: true);
        }
        return ColoredBox(
          color: c.sunken,
          child: Center(
            child: snap.hasError
                ? VIcon(G.image, size: 22, color: c.inkFaint)
                : SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.inkSoft)),
          ),
        );
      },
    );
  }
}

void openImageViewer(BuildContext context, Attachment a) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (context, _, _) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    maxScale: 5,
                    child: Center(
                      child: EncryptedImage(attachment: a, fit: BoxFit.contain),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Semantics(
                    button: true,
                    label: 'Close',
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: const VIcon(G.close, size: 18, color: Colors.white, stroke: 2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ),
  );
}
