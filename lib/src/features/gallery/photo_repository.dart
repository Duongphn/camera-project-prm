import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Quản lý ảnh đã chụp lưu trong thư mục riêng của app.
class PhotoRepository {
  Directory? _cached;

  Future<Directory> _photosDir() async {
    if (_cached != null) return _cached!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}photos');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return _cached = dir;
  }

  Future<File> savePhoto(Uint8List jpegBytes) async {
    final dir = await _photosDir();
    final name = 'DOKA_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    return file.writeAsBytes(jpegBytes, flush: true);
  }

  /// Ảnh mới nhất trước.
  Future<List<File>> listPhotos() async {
    final dir = await _photosDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.jpg'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<void> deletePhoto(File file) async {
    if (file.existsSync()) {
      await file.delete();
    }
  }
}
