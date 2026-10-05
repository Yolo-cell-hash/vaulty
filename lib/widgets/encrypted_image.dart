import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/memory.dart';
import '../services/attachment_store.dart';
import '../theme/app_theme.dart';
import 'common.dart';
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
            child: snap.hasError ? VIcon(G.image, size: 22, color: c.inkFaint) : Spinner(size: 18, color: c.inkSoft),
          ),
        );
      },
    );
  }
}

void openImageViewer(BuildContext context, Attachment a) {
  // iOS: the backdrop belongs to the page, so it can fade as the photo is
  // dragged away. Android keeps the route's barrier. From the root, so it
  // fills the screen even when opened inside an editor sheet.
  final ios = context.isCupertino;
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: ios ? null : Colors.black87,
      pageBuilder: (context, _, _) => _ImageViewer(attachment: a, dragToDismiss: ios),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ),
  );
}

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.attachment, required this.dragToDismiss});

  final Attachment attachment;

  /// Swipe the photo up or down to close it, as in Photos.
  final bool dragToDismiss;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  final _zoom = TransformationController();
  double _dy = 0;
  bool _dragging = false;
  bool _zoomed = false;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  void _dragEnd(DragEndDetails d) {
    if (_dy.abs() > 110 || (d.primaryVelocity ?? 0).abs() > 900) return _close();
    setState(() {
      _dragging = false;
      _dy = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    // A zoomed photo pans instead.
    final drag = widget.dragToDismiss && !_zoomed;
    final fade = widget.dragToDismiss ? (1 - _dy.abs() / 400).clamp(0.0, 1.0) : 0.0;
    final settle = Duration(milliseconds: _dragging ? 0 : 220);
    return GestureDetector(
      onTap: _close,
      onVerticalDragStart: drag ? (_) => setState(() => _dragging = true) : null,
      onVerticalDragUpdate: drag ? (d) => setState(() => _dy += d.delta.dy) : null,
      onVerticalDragEnd: drag ? _dragEnd : null,
      child: AnimatedContainer(
        duration: settle,
        color: Colors.black.withValues(alpha: .87 * fade),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: settle,
                    curve: Curves.easeOutCubic,
                    transform: Matrix4.translationValues(0, _dy, 0),
                    child: InteractiveViewer(
                      transformationController: _zoom,
                      maxScale: 5,
                      onInteractionEnd: (_) => setState(() => _zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01),
                      child: Center(
                        child: EncryptedImage(attachment: widget.attachment, fit: BoxFit.contain),
                      ),
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
                      onTap: _close,
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
    );
  }
}
