import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Consistent success/error snackbars so every action gives visible feedback.
void showAppFeedback(BuildContext context, String message,
    {bool isError = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
      backgroundColor: isError ? AppTheme.danger : AppTheme.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: Duration(seconds: isError ? 4 : 2),
    ),
  );
}
