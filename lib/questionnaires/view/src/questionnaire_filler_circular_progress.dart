import 'dart:math';

import 'package:collection/collection.dart';
import 'package:faiadashu/questionnaires/model/model.dart';
import 'package:faiadashu/questionnaires/view/view.dart'
    show QuestionnaireResponseFiller;
import 'package:flutter/material.dart';

/// A circular progress indicator for the filling of a [QuestionnaireModel]
class QuestionnaireFillerCircularProgress extends StatelessWidget {
  final double radius;

  static const double defaultRadius = 36.0;

  const QuestionnaireFillerCircularProgress({
    this.radius = defaultRadius,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: radius,
      height: radius,
      child: AnimatedBuilder(
        animation:
            QuestionnaireResponseFiller.of(context).questionnaireResponseModel,
        builder: (_, __) => CustomPaint(
          painter: _ProgressPainter(
            radius,
            colors: QuestionnaireResponseFiller.of(context)
                .questionnaireResponseModel
                .orderedResponseItemModels()
                .where((rim) => rim.isAnswerable)
                .map<Color?>(
              (rim) {
                return rim.isAnswered ? Colors.green : null;
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  final double radius;
  final Iterable<Color?> colors;

  static const double strokeWidth = 4.0;

  _ProgressPainter(this.radius, {required this.colors}) : super();

  final Paint _inactive = Paint()
    ..color = Colors.black12
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    const doublePi = pi + pi;

    canvas.drawArc(
      Offset.zero & Size(radius - strokeWidth, radius - strokeWidth),
      0,
      doublePi,
      false,
      _inactive,
    );

    final paint = Paint()
      ..color = Colors.pink
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final sweepAngle = doublePi / colors.length;

    colors.forEachIndexed((i, sweepColor) {
      if (sweepColor != null) {
        canvas.drawArc(
          Offset.zero & Size(radius - strokeWidth, radius - strokeWidth),
          i * sweepAngle,
          sweepAngle,
          false,
          paint,
        );
      }
    });
  }

  // OPTIMIZE: Come up with a criterion
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
