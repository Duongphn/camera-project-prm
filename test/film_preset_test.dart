import 'package:doka_app/src/features/filters/film_preset.dart';
import 'package:doka_app/src/features/filters/film_shader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('có đủ 10 preset, id không trùng', () {
    expect(filmPresets.length, 10);
    final ids = filmPresets.map((p) => p.id).toSet();
    expect(ids.length, filmPresets.length);
  });

  test('preset đầu tiên là trung tính (ảnh gốc)', () {
    expect(filmPresets.first.isNeutral, isTrue);
    expect(filmPresets.skip(1).any((p) => p.isNeutral), isFalse);
  });

  test('packFilmUniforms đúng số lượng và thứ tự khớp shader', () {
    // Shader khai báo 19 float: u_size(2) + 9 scalar + seed... xem film.frag.
    final u = packFilmUniforms(
      filmPresets.first,
      width: 100,
      height: 200,
      seed: 7,
    );
    expect(u.length, 19);
    expect(u[0], 100); // u_size.x
    expect(u[1], 200); // u_size.y
    expect(u[2], 0); // exposure trung tính
    expect(u[3], 1); // contrast trung tính
    expect(u[10], 7); // seed
    expect(u.sublist(11, 14), [0, 0, 0]); // shadow tint
    expect(u[14], 0); // shadow strength
    expect(u.sublist(15, 18), [1, 1, 1]); // highlight tint
    expect(u[18], 0); // highlight strength
  });

  test('mọi preset đóng gói được với giá trị hữu hạn trong khoảng hợp lệ', () {
    for (final p in filmPresets) {
      final u = packFilmUniforms(p, width: 1, height: 1);
      expect(u.length, 19, reason: p.id);
      for (final v in u) {
        expect(v.isFinite, isTrue, reason: p.id);
      }
      expect(p.saturation, inInclusiveRange(0, 2), reason: p.id);
      expect(p.grain, inInclusiveRange(0, 1), reason: p.id);
      expect(p.fade, inInclusiveRange(0, 1), reason: p.id);
      expect(p.vignette, inInclusiveRange(0, 1), reason: p.id);
    }
  });
}
