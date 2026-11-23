import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Reusable KuhuGrantha brand badge — compact logo + name strip
/// Used as a consistent branding header across all portal views.
class KgplBrandBadge extends StatelessWidget {
  final double logoSize;
  final bool showText;
  final bool dark;

  const KgplBrandBadge({
    super.key,
    this.logoSize = 40,
    this.showText = true,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: dark
            ? AppTheme.primaryNavy.withOpacity(0.85)
            : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.accentGold.withOpacity(0.35),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: logoSize,
            height: logoSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.accentGold, width: 1.5),
              color: Colors.white,
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.school,
                  color: AppTheme.accentGold,
                  size: logoSize * 0.6,
                ),
              ),
            ),
          ),
          if (showText) ...[
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'KuhuGrantha',
                  style: TextStyle(
                    color: AppTheme.accentGold,
                    fontWeight: FontWeight.w700,
                    fontSize: logoSize * 0.35,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'Private Limited',
                  style: TextStyle(
                    color: dark
                        ? Colors.white54
                        : Colors.white.withOpacity(0.7),
                    fontSize: logoSize * 0.26,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Full-width gradient page header banner with logo — used at top of each major view
class KgplPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget>? actions;

  const KgplPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryNavy,
            AppTheme.primaryNavy.withOpacity(0.85),
            const Color(0xFF1E3A5F),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.accentGold.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentGold.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.accentGold, width: 2),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accentGold.withOpacity(0.3),
                  blurRadius: 12,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.school,
                  color: AppTheme.accentGold,
                  size: 28,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Title section
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: AppTheme.accentGold, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.65),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'KuhuGrantha Private Limited',
                  style: TextStyle(
                    color: AppTheme.accentGold.withOpacity(0.7),
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Actions
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}
