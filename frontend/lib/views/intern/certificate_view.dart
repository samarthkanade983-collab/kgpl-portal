import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/device_file_downloader.dart';
import '../../core/utils/pdf_certificate.dart';

class CertificateView extends StatefulWidget {
  const CertificateView({super.key});

  @override
  State<CertificateView> createState() => _CertificateViewState();
}

class _CertificateViewState extends State<CertificateView> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  Map<String, dynamic>? _certData;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _fetchEligibility();
  }

  Future<void> _fetchEligibility() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final res = await _api.get(ApiConfig.internCertificate);
      if (!mounted) return;
      setState(() {
        _certData = res;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e.toString();
      });
    }
  }

  Widget _milestoneRow(
      {required bool done,
      required String doneText,
      required String pendingText,
      bool notApplicable = false}) {
    final color = notApplicable
        ? AppTheme.textMuted
        : done
            ? AppTheme.success
            : AppTheme.textSecondary;
    return Row(
      children: [
        Icon(
          notApplicable
              ? Icons.info_outline
              : done
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
          color: notApplicable ? AppTheme.textMuted : done ? AppTheme.success : Colors.grey,
          size: 18,
        ),
        const SizedBox(width: 8),
        Text(
          notApplicable ? pendingText : done ? doneText : pendingText,
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontWeight: done && !notApplicable
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _certificateCard({
    required String internName,
    required String internCode,
    required String dept,
    required String serial,
    required String bodyText,
    required String signerName,
    required String signerTitle,
    required String organization,
    required String issueDate,
  }) {
    return Container(
      width: 760,
      padding: const EdgeInsets.all(44),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: const Color(0xFFD4AF37), width: 3), // Rich Gold border
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: const Color(0xFFD4AF37).withOpacity(0.12),
            blurRadius: 36,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Official KuhuGrantha Logo Seal
          Container(
            width: 72,
            height: 72,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFD4AF37), width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD4AF37).withOpacity(0.25),
                  blurRadius: 14,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.workspace_premium,
                    color: Color(0xFFB45309),
                    size: 40),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'KUHUGRANTHA PRIVATE LIMITED (KGPL)',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: AppTheme.primaryNavy,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'CERTIFICATE OF COMPLETION',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'THIS IS PROUDLY PRESENTED TO',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            internName.toUpperCase(),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppTheme.primaryNavy,
              decoration: TextDecoration.underline,
              decorationColor: Color(0xFFD4AF37),
              decorationThickness: 2,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Intern ID: $internCode',
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              bodyText,
              style: const TextStyle(
                  fontSize: 14, color: AppTheme.textSecondary, height: 1.6),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 36),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(signerName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(signerTitle,
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 11)),
                  Text(organization,
                      style: const TextStyle(
                          color: Color(0xFFD4AF37),
                          fontWeight: FontWeight.w600,
                          fontSize: 11)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFFCD34D)),
                    ),
                    child: Text('VERIFIED: $serial',
                        style: const TextStyle(
                            fontFamily: 'Courier',
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: Color(0xFF92400E))),
                  ),
                  const SizedBox(height: 4),
                  Text('Issued: $issueDate',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 11)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 42, color: AppTheme.textMuted),
              const SizedBox(height: 16),
              const Text('Unable to load certificate status',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _fetchEligibility,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final bool isEligible = _certData?['eligible'] == true;
    final Map<String, dynamic> certificate =
        ((_certData?['certificate'] as Map?) ?? const {})
            .cast<String, dynamic>();
    final String internName =
        (certificate['recipient_name'] ?? _certData?['intern_name'] ?? 'Intern')
            .toString();
    final String internCode =
        (certificate['intern_code'] ?? _certData?['intern_code'] ?? 'INT-2026')
            .toString();
    final String dept = (certificate['department'] ??
            _certData?['department'] ??
            'Software Engineering')
        .toString();
    final String serial = (certificate['serial'] ??
            _certData?['certificate_serial'] ??
            'KGPL-CERT-2026-0001')
        .toString();
    final String bodyText = (certificate['body_text'] ??
            'for outstanding dedication and successfully fulfilling all curriculum requirements, '
                'practical assignments, interactive SOP certifications, and video training modules '
                'in the $dept Department.')
        .toString();
    final String signerName =
        (certificate['signer_name'] ?? 'Sarah Jenkins').toString();
    final String signerTitle =
        (certificate['signer_title'] ?? 'Head of Talent & Human Resources')
            .toString();
    final String organization =
        (certificate['organization'] ?? 'KuhuGrantha Pvt Ltd').toString();
    final String issueDate = (certificate['issue_date'] ??
            DateTime.now().toIso8601String().substring(0, 10))
        .toString();
    final int pendingVideos = _certData?['pending_videos_count'] ?? 0;
    final int pendingMaterials = _certData?['pending_materials_count'] ?? 0;
    final int pendingTests = _certData?['pending_tests_count'] ?? 0;
    final int assignedCourses =
        (_certData?['assigned_courses_count'] as num?)?.toInt() ?? 0;
    final int totalVideos = (_certData?['total_videos'] as num?)?.toInt() ?? 0;
    final int totalMaterials =
        (_certData?['total_materials'] as num?)?.toInt() ?? 0;
    final int totalModuleTests =
        (_certData?['total_module_tests_count'] as num?)?.toInt() ?? 0;
    final int pendingModuleTests =
        (_certData?['pending_module_tests_count'] as num?)?.toInt() ?? 0;
    final int totalTests =
        (_certData?['total_tests_count'] as num?)?.toInt() ?? 0;
    final int progressPercent =
        (_certData?['progress_percent'] ?? 0).toDouble().round();

    final card = _certificateCard(
      internName: internName,
      internCode: internCode,
      dept: dept,
      serial: serial,
      bodyText: bodyText,
      signerName: signerName,
      signerTitle: signerTitle,
      organization: organization,
      issueDate: issueDate,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Internship Completion Certificate',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Issued automatically once every assigned course is completed — all video lessons watched, all SOPs read, and all module and scheduled assessments passed.',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),

          if (!isEligible) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lock_outline_rounded,
                          color: Color(0xFFD97706), size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          assignedCourses == 0
                              ? 'Certificate locked — no course assigned'
                              : 'Certificate locked — keep going!',
                          style: const TextStyle(
                              color: Color(0xFF92400E),
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TweenAnimationBuilder<double>(
                    tween: Tween(
                        begin: 0, end: (progressPercent / 100).clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (ctx, v, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: v,
                        minHeight: 8,
                        backgroundColor: const Color(0xFFF1F5F9),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFD97706)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$progressPercent% complete',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF92400E)),
                  ),
                  const SizedBox(height: 12),
                  if (assignedCourses == 0)
                    _milestoneRow(
                      done: false,
                      notApplicable: true,
                      doneText: '',
                      pendingText:
                          'No courses assigned yet — ask your Team Leader to assign one',
                    )
                  else ...[
                    _milestoneRow(
                      done: totalVideos > 0 && pendingVideos == 0,
                      notApplicable: totalVideos == 0,
                      doneText: 'All course video lessons watched',
                      pendingText: totalVideos == 0
                          ? 'No video lessons in assigned courses'
                          : '$pendingVideos video lesson(s) remaining',
                    ),
                    const SizedBox(height: 8),
                    _milestoneRow(
                      done: totalMaterials > 0 && pendingMaterials == 0,
                      notApplicable: totalMaterials == 0,
                      doneText: 'All SOP study materials read',
                      pendingText: totalMaterials == 0
                          ? 'No SOP materials in assigned courses'
                          : '$pendingMaterials SOP material(s) remaining',
                    ),
                    const SizedBox(height: 8),
                    _milestoneRow(
                      done: totalModuleTests > 0 && pendingModuleTests == 0,
                      notApplicable: totalModuleTests == 0,
                      doneText: 'All course module tests passed',
                      pendingText: totalModuleTests == 0
                          ? 'No course modules assigned'
                          : '$pendingModuleTests module test(s) pending',
                    ),
                    const SizedBox(height: 8),
                    _milestoneRow(
                      done: totalTests > 0 && pendingTests == 0,
                      notApplicable: totalTests == 0,
                      doneText: 'All scheduled MCQ assessments passed',
                      pendingText: totalTests == 0
                          ? 'No assessments scheduled'
                          : '$pendingTests assessment(s) pending',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
          ] else ...[
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutBack,
              builder: (ctx, v, child) =>
                  Transform.scale(scale: 0.9 + 0.1 * v, child: child),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFCCB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFA3E635)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.celebration_rounded,
                        color: Color(0xFF4D7C0F), size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Congratulations! Your course is complete and your certificate is unlocked.',
                        style: TextStyle(
                            color: Color(0xFF3F6212),
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Certificate Preview Card — blurred behind a lock until eligibility
          Center(
            child: isEligible
                ? card
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                        child: Opacity(opacity: 0.55, child: card),
                      ),
                      Container(
                        width: 760,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 110),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.92),
                                shape: BoxShape.circle,
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black12, blurRadius: 18)
                                ],
                              ),
                              child: const Icon(Icons.lock_rounded,
                                  size: 40, color: AppTheme.primaryNavy),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Certificate locked',
                              style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryNavy),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'You are $progressPercent% there — finish the milestones above to unlock.',
                              style: const TextStyle(
                                  fontSize: 13, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),

          const SizedBox(height: 26),

          Center(
            child: ElevatedButton.icon(
              icon: Icon(
                  isEligible
                      ? Icons.download_rounded
                      : Icons.lock_outline_rounded,
                  size: 20),
              label: Text(isEligible
                  ? 'Download Certificate (PDF)'
                  : 'Certificate Locked'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                backgroundColor: isEligible ? null : AppTheme.borderColor,
                foregroundColor: isEligible ? null : AppTheme.textMuted,
              ),
              onPressed: () async {
                if (!isEligible) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Your certificate unlocks automatically once every course lesson, SOP and assessment is complete.'),
                      backgroundColor: AppTheme.warning,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                try {
                  final pdf = buildCertificatePdf(
                    name: internName,
                    serial: serial,
                    course: dept,
                    date: issueDate,
                    organization: organization,
                    signerName: signerName,
                    signerTitle: signerTitle,
                    body: bodyText,
                  );
                  await downloadBytes('KGPL_Certificate_$serial.pdf', pdf,
                      mime: 'application/pdf');
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Certificate saved as KGPL_Certificate_$serial.pdf'),
                      backgroundColor: AppTheme.success,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Failed to generate certificate: $e'),
                        backgroundColor: AppTheme.danger),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
