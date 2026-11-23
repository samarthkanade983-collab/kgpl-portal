import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SopPdfEmbed extends StatelessWidget {
  final String url;
  final double height;

  const SopPdfEmbed({super.key, required this.url, this.height = 620});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: AppTheme.scaffoldBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: const Center(
        child: Text(
          'Inline PDF preview is available in the web portal. Use Open / Download to view this document.',
          style: TextStyle(color: AppTheme.textMuted),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}