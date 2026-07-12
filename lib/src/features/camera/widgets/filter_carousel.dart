import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../filters/film_preset.dart';

/// Dải chọn filter phim nằm ngang phía trên nút chụp. Mỗi chip mang đúng sắc
/// của cuốn phim — cả dải đọc như một kệ phim.
class FilterCarousel extends StatelessWidget {
  const FilterCarousel({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: DokaSpacing.lg),
        itemCount: filmPresets.length,
        separatorBuilder: (_, _) => const SizedBox(width: DokaSpacing.sm),
        itemBuilder: (context, index) {
          final preset = filmPresets[index];
          final selected = index == selectedIndex;
          final swatch = presetSwatch(preset);
          return GestureDetector(
            onTap: () => onSelected(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
              decoration: BoxDecoration(
                color: selected
                    ? Color.alphaBlend(
                        swatch.withValues(alpha: 0.16), DokaColors.surfaceHigh)
                    : DokaColors.surface,
                borderRadius: BorderRadius.circular(DokaRadius.chip),
                border: Border.all(
                  color: selected
                      ? DokaColors.brass.withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.06),
                  width: selected ? 1.2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nắp phim: chấm màu = sắc thật của preset.
                  Container(
                    width: selected ? 18 : 15,
                    height: selected ? 18 : 15,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: swatch,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.85),
                        width: selected ? 1.6 : 1,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: swatch.withValues(alpha: 0.6),
                                blurRadius: 8,
                                spreadRadius: 0.5,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: DokaSpacing.sm),
                  Text(
                    preset.name,
                    style: DokaType.chip.copyWith(
                      color: selected ? DokaColors.ink : DokaColors.inkMuted,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
