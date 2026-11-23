import 'package:flutter/material.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/kgpl_brand_badge.dart';

class CertificateManagementView extends StatefulWidget {
  const CertificateManagementView({super.key});

  @override
  State<CertificateManagementView> createState() => _CertificateManagementViewState();
}

class _CertificateManagementViewState extends State<CertificateManagementView> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  String? _loadError;
  List<dynamic> _items = [];
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCertificates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCertificates() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final res = await _api.get(ApiConfig.hrCertificates);
      if (!mounted) return;
      setState(() {
        _items = (res is Map ? res['certificates'] as List? : null) ?? [];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (_items.isEmpty) _loadError = e.toString();
      });
      _showSnackbar(e.toString(), isError: true);
    }
  }

  List<dynamic> get _visibleItems {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((item) {
      final cert = (item['certificate'] as Map?) ?? const {};
      final haystack = [
        item['intern_name'],
        item['email'],
        cert['intern_code'],
        cert['department'],
        cert['serial'],
      ].whereType<Object>().join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  void _showSnackbar(String msg, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? AppTheme.danger : AppTheme.primaryNavy,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? const Color(0xFFFCA5A5) : const Color(0xFF6EE7B7),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(dynamic item) async {
    final message = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CertificateEditorDialog(api: _api, item: item),
    );
    if (!mounted || message == null) return;
    _showSnackbar(message);
    _loadCertificates();
  }

  Future<void> _resetCertificate(dynamic item) async {
    final internId = (item['intern_user_id'] as num).toInt();
    final name = (item['intern_name'] ?? 'this intern').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reset certificate?'),
        content: Text(
          'This removes every custom certificate field for $name and restores the automatic defaults '
          '(intern name, code, department, Sarah Jenkins as signer, today\'s date and the generated serial).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset to defaults'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final res = await _api.delete(ApiConfig.hrCertificate(internId));
      final msg = (res is Map && res['message'] != null)
          ? res['message'].toString()
          : 'Certificate reset to defaults.';
      _showSnackbar(msg);
      _loadCertificates();
    } on ApiException catch (e) {
      _showSnackbar(e.message, isError: true);
    } catch (e) {
      _showSnackbar(e.toString(), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleItems;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KgplPageHeader(
            title: 'Certificates',
            subtitle: 'Review and personalise every intern completion certificate',
            icon: Icons.workspace_premium_outlined,
            actions: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withOpacity(0.35)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
                onPressed: _loadCertificates,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSummary(),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Search intern, code, department or serial',
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildList(visible)),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final customised = _items.where((i) => i['has_custom'] == true).length;
    final cards = <Widget>[
      _SummaryCard(
        label: 'Interns',
        value: '${_items.length}',
        hint: 'Completion certificates',
        icon: Icons.school_outlined,
        color: AppTheme.info,
      ),
      _SummaryCard(
        label: 'Customised',
        value: '$customised',
        hint: 'Edited by HR',
        icon: Icons.edit_document,
        color: AppTheme.accentGold,
      ),
      _SummaryCard(
        label: 'Using defaults',
        value: '${_items.length - customised}',
        hint: 'Automatic content',
        icon: Icons.auto_awesome_outlined,
        color: AppTheme.success,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          final width = (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [for (final card in cards) SizedBox(width: width, child: card)],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _buildList(List<dynamic> visible) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 42, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadCertificates,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (visible.isEmpty) {
      return const Center(
        child: Text(
          'No interns match your search.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
      );
    }

    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _CertificateRow(
        item: visible[index],
        onEdit: () => _openEditor(visible[index]),
        onReset: () => _resetCertificate(visible[index]),
      ),
    );
  }
}

class _CertificateRow extends StatelessWidget {
  const _CertificateRow({required this.item, required this.onEdit, required this.onReset});

  final dynamic item;
  final VoidCallback onEdit;
  final VoidCallback onReset;

  String get _name {
    final cert = (item['certificate'] as Map?) ?? const {};
    return (cert['recipient_name'] ?? item['intern_name'] ?? 'Intern').toString();
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'IN';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final Map cert = (item['certificate'] as Map?) ?? const {};
    final bool hasCustom = item['has_custom'] == true;
    final String status = (item['status'] ?? 'active').toString();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accentGold.withOpacity(0.5)),
                ),
                child: Text(
                  _initials(_name),
                  style: const TextStyle(
                    color: AppTheme.accentGold,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: hasCustom ? AppTheme.warningLight : AppTheme.successLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            hasCustom ? 'Customised' : 'Defaults',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: hasCustom ? AppTheme.warning : AppTheme.success,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.infoLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            status,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.info,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      (item['email'] ?? '').toString(),
                      style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      children: [
                        _metaChip(Icons.badge_outlined, '${cert['intern_code'] ?? '—'}'),
                        _metaChip(Icons.domain_outlined, '${cert['department'] ?? '—'}'),
                        _metaChip(Icons.tag, '${cert['serial'] ?? '—'}'),
                        _metaChip(Icons.event_outlined, '${cert['issue_date'] ?? '—'}'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Signed by ${cert['signer_name'] ?? '—'} · ${cert['signer_title'] ?? ''}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
              if (hasCustom) ...[
                TextButton.icon(
                  onPressed: onReset,
                  style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
                  icon: const Icon(Icons.restart_alt, size: 17),
                  label: const Text('Reset'),
                ),
                const SizedBox(width: 6),
              ],
              FilledButton.icon(
                onPressed: onEdit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('Edit certificate'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textMuted),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

class _CertificateEditorDialog extends StatefulWidget {
  const _CertificateEditorDialog({required this.api, required this.item});

  final ApiService api;
  final dynamic item;

  @override
  State<_CertificateEditorDialog> createState() => _CertificateEditorDialogState();
}

class _CertificateEditorDialogState extends State<_CertificateEditorDialog> {
  late final Map<String, dynamic> _cert;
  late final Map<String, TextEditingController> _controllers;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cert = ((widget.item['certificate'] as Map?) ?? const {}).cast<String, dynamic>();
    String value(String key, String fallback) =>
        (_cert[key] ?? fallback).toString();

    _controllers = {
      'recipient_name': TextEditingController(
        text: value('recipient_name', (widget.item['intern_name'] ?? '').toString()),
      ),
      'intern_code': TextEditingController(text: value('intern_code', '')),
      'department': TextEditingController(text: value('department', '')),
      'issue_date': TextEditingController(
        text: value('issue_date', DateTime.now().toIso8601String().substring(0, 10)),
      ),
      'serial': TextEditingController(text: value('serial', '')),
      'signer_name': TextEditingController(text: value('signer_name', 'Sarah Jenkins')),
      'signer_title': TextEditingController(
        text: value('signer_title', 'Head of Talent & Human Resources'),
      ),
      'organization': TextEditingController(text: value('organization', 'KuhuGrantha Pvt Ltd')),
      'body_text': TextEditingController(
        text: value(
          'body_text',
          'for outstanding dedication and successfully fulfilling all curriculum requirements, '
              'practical assignments, interactive SOP certifications, and video training modules.',
        ),
      ),
    };
    for (final controller in _controllers.values) {
      controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.removeListener(_refresh);
      controller.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String _text(String key) => _controllers[key]!.text.trim();

  Future<void> _pickDate() async {
    final current = DateTime.tryParse(_text('issue_date'));
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    _controllers['issue_date']!.text = picked.toIso8601String().substring(0, 10);
  }

  Future<void> _save() async {
    final recipientName = _text('recipient_name');
    final signerName = _text('signer_name');
    final bodyText = _text('body_text');
    final issueDate = _text('issue_date');

    String? error;
    if (recipientName.length < 2 || recipientName.length > 100) {
      error = 'Recipient name must be between 2 and 100 characters.';
    } else if (signerName.length < 2 || signerName.length > 100) {
      error = 'Signer name must be between 2 and 100 characters.';
    } else if (bodyText.length < 10 || bodyText.length > 1000) {
      error = 'Certificate body must be between 10 and 1000 characters.';
    } else if (issueDate.isNotEmpty &&
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(issueDate)) {
      error = 'Issue date must use YYYY-MM-DD format.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await widget.api.put(
        ApiConfig.hrCertificate((widget.item['intern_user_id'] as num).toInt()),
        {
          'recipient_name': recipientName,
          'intern_code': _text('intern_code'),
          'department': _text('department'),
          'body_text': bodyText,
          'signer_name': signerName,
          'signer_title': _text('signer_title'),
          'organization': _text('organization'),
          'issue_date': issueDate,
          'serial': _text('serial'),
        },
      );
      if (!mounted) return;
      final message = (res is Map && res['message'] != null)
          ? res['message'].toString()
          : 'Certificate updated successfully.';
      Navigator.of(context).pop(message);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final internName = (widget.item['intern_name'] ?? 'Intern').toString();
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppTheme.warningLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: AppTheme.warning,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Edit certificate',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          internName,
                          style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CertificatePreview(
                      organization: _text('organization'),
                      recipientName: _text('recipient_name'),
                      internCode: _text('intern_code'),
                      bodyText: _text('body_text'),
                      signerName: _text('signer_name'),
                      signerTitle: _text('signer_title'),
                      serial: _text('serial'),
                      issueDate: _text('issue_date'),
                    ),
                    const SizedBox(height: 20),
                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.dangerLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: AppTheme.danger, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(color: AppTheme.danger, fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final twoColumns = constraints.maxWidth >= 660;
                        final width = twoColumns ? (constraints.maxWidth - 16) / 2 : constraints.maxWidth;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            SizedBox(
                              width: width,
                              child: _field('Recipient name', 'recipient_name',
                                  required: true),
                            ),
                            SizedBox(
                              width: width,
                              child: _field('Intern ID', 'intern_code'),
                            ),
                            SizedBox(
                              width: width,
                              child: _field('Department', 'department'),
                            ),
                            SizedBox(
                              width: width,
                              child: _field(
                                'Issue date (YYYY-MM-DD)',
                                'issue_date',
                                suffix: IconButton(
                                  tooltip: 'Pick a date',
                                  icon: const Icon(Icons.event_outlined, size: 18),
                                  onPressed: _saving ? null : _pickDate,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: _field('Certificate serial', 'serial'),
                            ),
                            SizedBox(
                              width: width,
                              child: _field('Signer name', 'signer_name', required: true),
                            ),
                            SizedBox(
                              width: width,
                              child: _field('Signer title', 'signer_title'),
                            ),
                            SizedBox(
                              width: width,
                              child: _field('Organization', 'organization'),
                            ),
                            SizedBox(
                              width: constraints.maxWidth,
                              child: _field(
                                'Certificate body',
                                'body_text',
                                maxLines: 4,
                                required: true,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Leave Intern ID, Department, Signer title, Organization or Serial empty to fall back '
                      'to the automatic value for that intern.',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryNavy,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(_saving ? 'Saving…' : 'Save certificate'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    String key, {
    int maxLines = 1,
    bool required = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: _controllers[key],
      enabled: !_saving,
      maxLines: maxLines,
      maxLength: key == 'body_text' ? 1000 : null,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        suffixIcon: suffix,
        counterText: '',
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}

class _CertificatePreview extends StatelessWidget {
  const _CertificatePreview({
    required this.organization,
    required this.recipientName,
    required this.internCode,
    required this.bodyText,
    required this.signerName,
    required this.signerTitle,
    required this.serial,
    required this.issueDate,
  });

  final String organization;
  final String recipientName;
  final String internCode;
  final String bodyText;
  final String signerName;
  final String signerTitle;
  final String serial;
  final String issueDate;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gold, width: 2),
        boxShadow: [
          BoxShadow(color: gold.withOpacity(0.12), blurRadius: 18, spreadRadius: 1),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: gold, width: 1.5),
            ),
            child: const Icon(Icons.workspace_premium, color: Color(0xFFB45309), size: 26),
          ),
          const SizedBox(height: 10),
          Text(
            (organization.isEmpty ? 'KUHUGRANTHA PRIVATE LIMITED' : organization).toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: AppTheme.primaryNavy,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'CERTIFICATE OF COMPLETION',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'THIS IS PROUDLY PRESENTED TO',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.6,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            (recipientName.isEmpty ? 'INTERN NAME' : recipientName).toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: AppTheme.primaryNavy,
              decoration: TextDecoration.underline,
              decorationColor: gold,
              decorationThickness: 2,
            ),
          ),
          if (internCode.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                'Intern ID: $internCode',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            bodyText.isEmpty ? 'Certificate body text will appear here.' : bodyText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      signerName.isEmpty ? 'Signer name' : signerName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                    Text(
                      signerTitle,
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (serial.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFFCD34D)),
                      ),
                      child: Text(
                        'VERIFIED: $serial',
                        style: const TextStyle(
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    'Issued: ${issueDate.isEmpty ? '—' : issueDate}',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor, width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  hint,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
