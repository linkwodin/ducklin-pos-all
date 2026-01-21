import 'package:flutter/material.dart';

class NumericKeypad extends StatelessWidget {
  final Function(String) onNumberTap;
  final VoidCallback onBackspace;
  final VoidCallback? onClear;
  final bool showClearButton;

  const NumericKeypad({
    super.key,
    required this.onNumberTap,
    required this.onBackspace,
    this.onClear,
    this.showClearButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Row 1: 1, 2, 3
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildNumberButton('1', onNumberTap),
              const SizedBox(width: 12),
              _buildNumberButton('2', onNumberTap),
              const SizedBox(width: 12),
              _buildNumberButton('3', onNumberTap),
            ],
          ),
          const SizedBox(height: 8),
          // Row 2: 4, 5, 6
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildNumberButton('4', onNumberTap),
              const SizedBox(width: 12),
              _buildNumberButton('5', onNumberTap),
              const SizedBox(width: 12),
              _buildNumberButton('6', onNumberTap),
            ],
          ),
          const SizedBox(height: 8),
          // Row 3: 7, 8, 9
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildNumberButton('7', onNumberTap),
              const SizedBox(width: 12),
              _buildNumberButton('8', onNumberTap),
              const SizedBox(width: 12),
              _buildNumberButton('9', onNumberTap),
            ],
          ),
          const SizedBox(height: 8),
          // Row 4: Clear/Empty, 0, Backspace
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Clear button or empty space
              showClearButton && onClear != null
                  ? _buildActionButton(
                      icon: Icons.clear,
                      onTap: onClear!,
                      color: Colors.orange,
                    )
                  : const SizedBox(width: 60, height: 60),
              const SizedBox(width: 12),
              _buildNumberButton('0', onNumberTap),
              const SizedBox(width: 12),
              _buildActionButton(
                icon: Icons.backspace,
                onTap: onBackspace,
                color: Colors.red,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNumberButton(String number, Function(String) onTap) {
    return SizedBox(
      width: 60,
      height: 60,
      child: ElevatedButton(
        onPressed: () => onTap(number),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey[200],
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 2,
          padding: EdgeInsets.zero,
        ),
        child: Text(
          number,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
  }) {
    return SizedBox(
      width: 60,
      height: 60,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? Colors.grey[300],
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 2,
          padding: EdgeInsets.zero,
        ),
        child: Icon(icon, size: 24),
      ),
    );
  }
}

