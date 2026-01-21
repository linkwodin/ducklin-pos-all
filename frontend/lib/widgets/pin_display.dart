import 'package:flutter/material.dart';

class PINDisplay extends StatelessWidget {
  final int length;
  final int enteredLength;
  final bool obscureText;

  const PINDisplay({
    super.key,
    required this.length,
    required this.enteredLength,
    this.obscureText = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        length,
        (index) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: index < enteredLength
                ? Theme.of(context).primaryColor
                : Colors.grey[300],
            border: Border.all(
              color: index < enteredLength
                  ? Theme.of(context).primaryColor
                  : Colors.grey[400]!,
              width: 2,
            ),
          ),
          child: index < enteredLength && !obscureText
              ? Center(
                  child: Text(
                    '●',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

