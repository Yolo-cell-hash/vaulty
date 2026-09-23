import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'auth_service.dart';

/// On-device text recognition with Google ML Kit's bundled Latin model on
/// both iOS and Android. Images never leave the device.
class OcrService {
  OcrService._();

  static final _picker = ImagePicker();

  static Future<File?> pickImage(ImageSource source) async {
    final x = await AuthService.guardExternal(
      () => _picker.pickImage(source: source, maxWidth: 2000, imageQuality: 85),
    );
    return x == null ? null : File(x.path);
  }

  static Future<String> recognize(File image) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(image.path));
      return result.blocks.map((b) => b.lines.map((l) => l.text).join('\n')).join('\n');
    } finally {
      await recognizer.close();
    }
  }
}
