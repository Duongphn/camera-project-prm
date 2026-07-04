import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/gallery/photo_repository.dart';

final photoRepositoryProvider =
    Provider<PhotoRepository>((ref) => PhotoRepository());
