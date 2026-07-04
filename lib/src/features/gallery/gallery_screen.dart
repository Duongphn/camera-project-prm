import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../editor/edit_screen.dart';

/// Thư viện ảnh đã chụp trong app.
class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  late Future<List<File>> _photos;

  @override
  void initState() {
    super.initState();
    _photos = ref.read(photoRepositoryProvider).listPhotos();
  }

  void _reload() {
    setState(() {
      _photos = ref.read(photoRepositoryProvider).listPhotos();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Ảnh của bạn'),
      ),
      body: FutureBuilder<List<File>>(
        future: _photos,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white24),
            );
          }
          final photos = snapshot.data ?? const [];
          if (photos.isEmpty) {
            return const Center(
              child: Text(
                'Chưa có ảnh nào.\nQuay lại và bấm nút chụp thôi!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: photos.length,
            itemBuilder: (context, index) {
              final file = photos[index];
              return GestureDetector(
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _PhotoViewer(
                        photos: photos,
                        initialIndex: index,
                      ),
                    ),
                  );
                  _reload();
                },
                child: Image.file(
                  file,
                  fit: BoxFit.cover,
                  cacheWidth: 360,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PhotoViewer extends ConsumerStatefulWidget {
  const _PhotoViewer({required this.photos, required this.initialIndex});

  final List<File> photos;
  final int initialIndex;

  @override
  ConsumerState<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends ConsumerState<_PhotoViewer> {
  late final PageController _pageController;
  late List<File> _photos;
  late int _current;

  @override
  void initState() {
    super.initState();
    _photos = List.of(widget.photos);
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _deleteCurrent() async {
    final file = _photos[_current];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá ảnh này?'),
        content: const Text(
          'Ảnh chỉ bị xoá khỏi thư viện của app. '
          'Bản đã lưu trong thư viện máy (nếu có) vẫn còn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(photoRepositoryProvider).deletePhoto(file);
    if (!mounted) return;
    setState(() => _photos.removeAt(_current));
    if (_photos.isEmpty) {
      Navigator.of(context).pop();
    } else if (_current >= _photos.length) {
      setState(() => _current = _photos.length - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_current + 1}/${_photos.length}'),
        actions: [
          IconButton(
            tooltip: 'Chỉnh ảnh',
            onPressed: () async {
              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => EditScreen(file: _photos[_current]),
                ),
              );
              if (saved == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã lưu thành ảnh mới.')),
                );
              }
            },
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            onPressed: _deleteCurrent,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: _photos.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (context, index) => InteractiveViewer(
          maxScale: 5,
          child: Center(child: Image.file(_photos[index])),
        ),
      ),
    );
  }
}
