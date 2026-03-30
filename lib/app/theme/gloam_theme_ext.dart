import 'package:flutter/material.dart';

import 'gloam_color_extension.dart';

/// Convenience extension for accessing Gloam color tokens from BuildContext.
///
/// Usage: `context.gloam.accent`, `context.gloam.bgSurface`, etc.
extension GloamThemeContext on BuildContext {
  GloamColorExtension get gloam =>
      Theme.of(this).extension<GloamColorExtension>()!;
}
