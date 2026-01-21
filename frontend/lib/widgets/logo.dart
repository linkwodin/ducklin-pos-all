import 'package:flutter/material.dart';

class Logo extends StatelessWidget {
  final Color textColor;
  final double fontSize;

  const Logo({
    super.key,
    this.textColor = Colors.black,
    this.fontSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo.png',
      height: fontSize,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        // Try AVIF if PNG fails
        return Image.asset(
          'assets/images/logo.avif',
          height: fontSize,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // Fallback to text if both images fail to load
            return Text(
              '德靈公司 POS',
              style: TextStyle(
                color: textColor,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
              ),
            );
          },
        );
      },
    );
  }
}

