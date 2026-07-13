/// Một nút chỉnh nhanh: nhãn tiếng Việt hiển thị + prompt tiếng Anh gửi Gemini.
class QuickEdit {
  const QuickEdit(this.label, this.prompt);

  final String label;
  final String prompt;
}

/// 4 nút nhanh cho bản đầu. Prompt tiếng Anh để Gemini xử lý ổn định hơn.
const List<QuickEdit> quickEdits = [
  QuickEdit(
    'Xoá phông',
    'Keep the main subject sharp and unchanged. Cleanly blur or remove the '
        'background so the subject stands out. Do not alter the subject.',
  ),
  QuickEdit(
    'Đổi bầu trời',
    'Replace only the sky with a beautiful clear blue sky with soft clouds. '
        'Keep the foreground, subject and lighting consistent and realistic.',
  ),
  QuickEdit(
    'Nâng chất lượng',
    'Enhance this photo: increase sharpness and detail, reduce noise. Keep the '
        'exact same composition, colors and content. Do not add or remove anything.',
  ),
  QuickEdit(
    'Style phim',
    'Apply an analog film look: warm tones, soft contrast, gentle film grain, '
        'slightly faded highlights. Keep the composition and subject unchanged.',
  ),
];
