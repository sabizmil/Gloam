import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show highlight, Node;

/// A syntax-highlighted code view that works with [SelectionArea].
///
/// Drop-in replacement for [HighlightView] from flutter_highlight,
/// but uses [Text.rich] instead of [RichText] so the text participates
/// in Flutter's selection registrar for cross-widget text selection.
class SelectableHighlightView extends StatelessWidget {
  final String source;
  final String? language;
  final Map<String, TextStyle> theme;
  final EdgeInsetsGeometry? padding;
  final TextStyle? textStyle;

  SelectableHighlightView(
    String input, {
    super.key,
    this.language,
    this.theme = const {},
    this.padding,
    this.textStyle,
    int tabSize = 8,
  }) : source = input.replaceAll('\t', ' ' * tabSize);

  List<TextSpan> _convert(List<Node> nodes) {
    List<TextSpan> spans = [];
    var currentSpans = spans;
    List<List<TextSpan>> stack = [];

    void traverse(Node node) {
      if (node.value != null) {
        currentSpans.add(node.className == null
            ? TextSpan(text: node.value)
            : TextSpan(text: node.value, style: theme[node.className!]));
      } else if (node.children != null) {
        List<TextSpan> tmp = [];
        currentSpans
            .add(TextSpan(children: tmp, style: theme[node.className!]));
        stack.add(currentSpans);
        currentSpans = tmp;

        for (final n in node.children!) {
          traverse(n);
          if (n == node.children!.last) {
            currentSpans = stack.isEmpty ? spans : stack.removeLast();
          }
        }
      }
    }

    for (var node in nodes) {
      traverse(node);
    }
    return spans;
  }

  static const _rootKey = 'root';
  static const _defaultFontColor = Color(0xff000000);
  static const _defaultBackgroundColor = Color(0xffffffff);

  @override
  Widget build(BuildContext context) {
    var baseStyle = TextStyle(
      fontFamily: 'monospace',
      color: theme[_rootKey]?.color ?? _defaultFontColor,
    );
    if (textStyle != null) {
      baseStyle = baseStyle.merge(textStyle);
    }

    return Container(
      color: theme[_rootKey]?.backgroundColor ?? _defaultBackgroundColor,
      padding: padding,
      child: Text.rich(
        TextSpan(
          style: baseStyle,
          children:
              _convert(highlight.parse(source, language: language).nodes!),
        ),
      ),
    );
  }
}
