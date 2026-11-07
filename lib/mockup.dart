// Mockup / planned styling, shared by every screen. Pink means "planned,
// not built yet" -- deliberately not grey, which means "exists but
// unavailable on this connection".

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Mockup styling: "planned, not built yet". Deliberately NOT grey (grey means
// unavailable/locked): a dashed pink "blueprint" outline + MOCKUP tag.
// ---------------------------------------------------------------------------

const kMockupColor = Color(0xFFF472B6);
const _plannedTooltip =
    'Planned: the server has this, but Scroll does not show it yet.';
const _mockupTooltip =
    'Mockup: a design placeholder with sample data. Not built yet and not '
    'connected to the server.';

class MockupTag extends StatelessWidget {
  /// MOCKUP = a design placeholder with sample data. PLANNED = a real server
  /// feature Scroll doesn't show yet (same pink: planned, not built).
  final String label;
  const MockupTag({super.key, this.label = 'MOCKUP'});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label == 'MOCKUP' ? _mockupTooltip : _plannedTooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          // Solid, so the dashed border it sits on doesn't show through.
          color: const Color(0xFF2A1724),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: kMockupColor.withValues(alpha: 0.6)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: kMockupColor,
          ),
        ),
      ),
    );
  }
}

/// Dashed pink outline + MOCKUP tag around a card/tile that isn't built yet.
class MockupOutline extends StatelessWidget {
  final Widget child;
  final double radius;

  /// The tag on the border: "MOCKUP", "PLANNED", or null for none.
  final String? tag;

  /// Put the tag on the left (icon tiles keep their right corner for a
  /// count badge).
  final bool tagLeft;
  const MockupOutline({
    super.key,
    required this.child,
    this.radius = 10,
    this.tag = 'MOCKUP',
    this.tagLeft = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(kMockupColor, radius),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          // Sits on the dashed border, clear of the content.
          if (tag != null)
            Positioned(
              top: -9,
              left: tagLeft ? 12 : null,
              right: tagLeft ? null : 12,
              child: MockupTag(label: tag!),
            ),
        ],
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DashedRRectPainter(this.color, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

/// A whole screen that is a mockup: pink banner on top, the mockup below.
class MockupFrame extends StatelessWidget {
  final Widget child;
  final String what;
  const MockupFrame({super.key, required this.child, required this.what});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: kMockupColor.withValues(alpha: 0.10),
            border: const Border(
              bottom: BorderSide(color: kMockupColor, width: 1),
            ),
          ),
          child: Row(
            children: [
              const MockupTag(),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$what — design placeholder with sample data. Not built yet; '
                  'nothing here reads or writes the server.',
                  style: const TextStyle(fontSize: 12, color: kMockupColor),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
