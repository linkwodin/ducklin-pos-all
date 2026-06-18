import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/app_localizations.dart';

class MediaPicker {
  static final _picker = ImagePicker();

  static Future<List<String>> pickImages({bool fromCamera = false}) async {
    if (fromCamera) {
      final photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo?.path != null) return [photo!.path];
      return [];
    }
    final photos = await _picker.pickMultiImage();
    return photos.map((p) => p.path).toList();
  }

  static Future<List<String>> pickDocuments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    return result?.paths.whereType<String>().toList() ?? [];
  }

  static Future<void> showSourceSheet(
    BuildContext context, {
    required void Function(List<String> paths) onPicked,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(l10n.takePhoto),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(l10n.chooseFromGallery),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(l10n.chooseFile),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    List<String> paths;
    switch (choice) {
      case 'camera':
        paths = await pickImages(fromCamera: true);
      case 'gallery':
        paths = await pickImages(fromCamera: false);
      case 'file':
        paths = await pickDocuments();
      default:
        paths = [];
    }
    if (paths.isNotEmpty) onPicked(paths);
  }
}
