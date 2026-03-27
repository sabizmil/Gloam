import 'package:flutter/material.dart';

import '../app/theme/typography.dart';

/// The `// MONOSPACE SECTION HEADER` pattern used throughout Gloam.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.padding, this.color});

  final String text;
  final EdgeInsets? padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Text(
        '// $text',
        style: color != null
            ? GloamTypography.sectionHeader.copyWith(color: color)
            : GloamTypography.sectionHeader,
      ),
    );
  }
}
