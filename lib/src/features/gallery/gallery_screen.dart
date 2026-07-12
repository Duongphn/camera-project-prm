import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
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
      backgroundColor: DokaColors.body,
      appBar: AppBar(
        backgroundColor: DokaColors.body,
        foregroundColor: DokaColors.ink,
        elevation: 0,
        title: const Text('Ảnh của bạn', style: DokaType.title),
      ),
      body: FutureBuilder<List<File>>(
        future: _photos,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: DokaColors.brassDeep),
            );
          }
          final photos = snapshot.data ?? const [];
          if (photos.isEmpty) return _buildEmpty();
          return GridView.builder(
            padding: const EdgeInsets.all(DokaSpacing.md),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: DokaSpacing.sm,
              crossAxisSpacing: DokaSpacing.sm,
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    color: DokaColors.surface,
                    child: Image.file(
                      file,
                      fit: BoxFit.cover,
                      cacheWidth: 360,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: DokaColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: const Icon(Icons.camera_roll_outlined,
                color: DokaColors.brass, size: 32),
          ),
          const SizedBox(height: DokaSpacing.lg),
          const Text(
            'Chưa có ảnh nào',
            style: DokaType.title,
          ),
          const SizedBox(height: DokaSpacing.sm),
          const Text(
            'Quay lại và bấm nút chụp thôi!',
            textAlign: TextAlign.center,
            style: DokaType.caption,
          ),
        ],
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
        backgroundColor: DokaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DokaRadius.card),
        ),
        title: const Text('Xoá ảnh này?', style: DokaType.title),
        content: const Text(
          'Ảnh chỉ bị xoá khỏi thư viện của app. '
          'Bản đã lưu trong thư viện máy (nếu có) vẫn còn.',
          style: DokaType.caption,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: DokaColors.inkMuted),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: DokaColors.shutter),
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
      backgroundColor: DokaColors.body,
      appBar: AppBar(
        backgroundColor: DokaColors.body,
        foregroundColor: DokaColors.ink,
        elevation: 0,
        title: Text(
          '${_current + 1} / ${_photos.length}',
          style: DokaType.meter,
        ),
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
