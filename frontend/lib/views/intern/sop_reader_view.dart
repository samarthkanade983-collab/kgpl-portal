import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/device_file_downloader.dart';
import '../../core/utils/sop_pdf_embed.dart';
import '../../core/utils/device_file_picker.dart';
import '../../core/utils/picked_file.dart';
import '../../widgets/kgpl_brand_badge.dart';

class SopReaderView extends StatefulWidget {
  const SopReaderView({super.key});

  @override
  State<SopReaderView> createState() => _SopReaderViewState();
}

class _SopReaderViewState extends State<SopReaderView> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  List<dynamic> _sops = [];
  Map<String, dynamic>? _selectedSop;
  String _filter = 'all'; // 'all', 'unread', 'read'
  String _search = '';
  final _searchController = TextEditingController();
  Map<String, dynamic>? _preview;
  bool _previewLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchSops();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchSops() async {
    setState(() => _isLoading = true);
    try {
      final res = await _api.get(ApiConfig.internSops);
      final sops = (res['sops'] as List?) ?? [];
      setState(() {
        _sops = sops;
        if (sops.isNotEmpty && _selectedSop == null) {
          _selectedSop = sops[0];
        } else if (_selectedSop != null) {
          final updated = sops.firstWhere(
            (s) => s['id'] == _selectedSop!['id'],
            orElse: () => sops.first,
          );
          _selectedSop = updated;
        }
        _isLoading = false;
      });
      if (_selectedSop != null) _loadPreview(_selectedSop!);
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPreview(Map<String, dynamic> sop) async {
    setState(() {
      _previewLoading = true;
      _preview = null;
    });
    try {
      final rawId = sop['id'];
      final int id = rawId is int ? rawId : int.parse(rawId.toString());
      final res = await _api.get(ApiConfig.internSopPreview(id));
      if (!mounted) return;
      final bool stillSelected = _selectedSop != null && _selectedSop!['id'] == sop['id'];
      setState(() {
        _preview = stillSelected && res is Map ? Map<String, dynamic>.from(res) : null;
        _previewLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _previewLoading = false;
        _preview = {'kind': 'missing', 'ext': ''};
      });
    }
  }

  void _openLightbox(String url, String caption) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(40),
                      child: Text('Image could not be loaded', style: TextStyle(color: Colors.white70)),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 16,
              right: 60,
              child: Text(
                caption,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markAsRead(int materialId) async {
    try {
      await _api.post(ApiConfig.internMarkSopRead, {
        'material_id': materialId,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ SOP compliance successfully recorded in your learning profile!'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );

      _fetchSops();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Compliance error: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  Future<void> _deleteSop(int sopId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete SOP Document?'),
        content: const Text('Are you sure you want to remove this SOP document from the corporate portal?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _api.delete('${ApiConfig.tlSops}/$sopId');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SOP document deleted successfully!'), backgroundColor: AppTheme.success),
        );
        _fetchSops();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete SOP: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  Future<void> _downloadSopFile(String filePath, String title) async {
    if (filePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file is attached to this SOP yet.'), backgroundColor: AppTheme.warning),
      );
      return;
    }
    if (filePath.startsWith('http')) {
      openExternalUrl(filePath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opened "$title" in a new tab'), backgroundColor: AppTheme.info, behavior: SnackBarBehavior.floating),
      );
      return;
    }
    try {
      final url = '${ApiConfig.serverOrigin}$filePath';
      final bytes = await _api.getBytes(url);
      final fileName = filePath.split('/').last;
      await downloadBytes(fileName.isNotEmpty ? fileName : '$title.pdf', bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.download_done_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Saved ${fileName.isNotEmpty ? fileName : title} to your downloads')),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  void _openUploadDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _UploadSopDialog(
        onSuccess: () {
          Navigator.pop(ctx);
          _fetchSops();
        },
      ),
    );
  }

  List<dynamic> get _filteredSops {
    return _sops.where((s) {
      final title = (s['title'] ?? '').toString().toLowerCase();
      final category = (s['category'] ?? '').toString().toLowerCase();
      final matchesSearch = _search.isEmpty || title.contains(_search.toLowerCase()) || category.contains(_search.toLowerCase());
      final isRead = s['is_read'] == 1 || s['is_read'] == true;

      if (_filter == 'read') return matchesSearch && isRead;
      if (_filter == 'unread') return matchesSearch && !isRead;
      return matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final bool canUpload = auth.userRole == 'team_leader' || auth.userRole == 'hr_admin';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KgplPageHeader(
            title: 'Standard Operating Procedures (SOP) & Technical Manuals',
            subtitle: 'Verified corporate runbooks, deployment guides, cloud policies, and compliance procedures.',
            icon: Icons.auto_stories_rounded,
            actions: [
              if (canUpload) ...[
                ElevatedButton.icon(
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                  label: const Text('+ Publish New SOP (PDF/Excel/Photo)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                  ),
                  onPressed: _openUploadDialog,
                ),
                const SizedBox(width: 12),
              ],
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white70),
                label: const Text('Refresh', style: TextStyle(color: Colors.white70)),
                onPressed: _fetchSops,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white30),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Main 2-Pane Content
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left 35%: SOP Library
                Expanded(
                  flex: 35,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Search bar
                        SizedBox(
                          height: 42,
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search_rounded, size: 18),
                              hintText: 'Search SOPs by title or keyword...',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              suffixIcon: _search.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 16),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _search = '');
                                      },
                                    )
                                  : null,
                            ),
                            onChanged: (val) => setState(() => _search = val.trim()),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Filter chips
                        Row(
                          children: [
                            _filterChip('all', 'All (${_sops.length})'),
                            const SizedBox(width: 6),
                            _filterChip(
                              'unread',
                              'Unread (${_sops.where((s) => s['is_read'] != 1 && s['is_read'] != true).length})',
                            ),
                            const SizedBox(width: 6),
                            _filterChip(
                              'read',
                              'Read (${_sops.where((s) => s['is_read'] == 1 || s['is_read'] == true).length})',
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),

                        // SOP List
                        Expanded(
                          child: _isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : _filteredSops.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.folder_open_rounded, size: 48, color: Colors.grey.shade400),
                                          const SizedBox(height: 8),
                                          const Text('No SOP documents found', style: TextStyle(color: AppTheme.textMuted)),
                                        ],
                                      ),
                                    )
                                  : ListView.separated(
                                      itemCount: _filteredSops.length,
                                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                                      itemBuilder: (ctx, i) {
                                        final sop = _filteredSops[i];
                                        final bool isSelected = _selectedSop != null && _selectedSop!['id'] == sop['id'];
                                        final bool isRead = sop['is_read'] == 1 || sop['is_read'] == true;
                                        final fileType = _displayType(sop);

                                        return InkWell(
                                          onTap: () {
                                            setState(() => _selectedSop = sop);
                                            _loadPreview(sop);
                                          },
                                          borderRadius: BorderRadius.circular(12),
                                          child: Container(
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: isSelected ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0),
                                                width: isSelected ? 1.8 : 1.0,
                                              ),
                                              boxShadow: isSelected
                                                  ? [
                                                      BoxShadow(
                                                        color: const Color(0xFF6366F1).withOpacity(0.12),
                                                        blurRadius: 8,
                                                        offset: const Offset(0, 2),
                                                      ),
                                                    ]
                                                  : null,
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    _formatTypeBadge(fileType),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        sop['title'] ?? 'SOP Document',
                                                        style: TextStyle(
                                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                                          fontSize: 13,
                                                          color: isSelected ? const Color(0xFF312E81) : AppTheme.textPrimary,
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Text(
                                                      '${sop['file_size_kb'] ?? 150} KB • ${sop['author'] ?? 'KGPL Infra'}',
                                                      style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: isRead ? AppTheme.successLight : AppTheme.warningLight,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        isRead ? 'VERIFIED READ' : 'ACTION REQUIRED',
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          fontWeight: FontWeight.bold,
                                                          color: isRead ? AppTheme.success : AppTheme.warning,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 20),

                // Right 65%: In-App Document Reader Canvas
                Expanded(
                  flex: 65,
                  child: _selectedSop == null
                      ? Container(
                          decoration: BoxDecoration(
                            color: AppTheme.cardBackground,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Center(
                            child: Text('Select an SOP document from the left library to inspect'),
                          ),
                        )
                      : _buildReaderCanvas(_selectedSop!, canUpload),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _displayType(Map<String, dynamic> sop) {
    final p = (sop['file_path'] ?? '').toString().toLowerCase();
    final ext = p.contains('.') ? p.split('.').last : '';
    if (ext == 'pdf') return 'pdf';
    if (['xlsx', 'xls', 'csv'].contains(ext)) return 'excel';
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'].contains(ext)) return 'photo';
    if (['docx', 'doc'].contains(ext)) return 'doc';
    if (['md', 'txt', 'markdown'].contains(ext)) return 'md';
    return (sop['fileType'] ?? sop['material_type'] ?? 'sop').toString().toLowerCase();
  }

  Widget _formatTypeBadge(String fileType) {
    Color bg = const Color(0xFFEEF2FF);
    Color fg = const Color(0xFF4F46E5);
    String label = 'SOP';
    IconData icon = Icons.description_rounded;

    if (fileType.contains('pdf')) {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFFDC2626);
      label = 'PDF';
      icon = Icons.picture_as_pdf_rounded;
    } else if (fileType.contains('excel') || fileType.contains('xls') || fileType.contains('csv')) {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF16A34A);
      label = 'EXCEL';
      icon = Icons.table_chart_rounded;
    } else if (fileType.contains('photo') || fileType.contains('jpg') || fileType.contains('png') || fileType.contains('jpeg')) {
      bg = const Color(0xFFF3E8FF);
      fg = const Color(0xFF9333EA);
      label = 'PHOTO';
      icon = Icons.image_rounded;
    } else if (fileType.contains('doc')) {
      bg = const Color(0xFFE0F2FE);
      fg = const Color(0xFF0284C7);
      label = 'DOCX';
      icon = Icons.article_rounded;
    } else if (fileType == 'md' || fileType.contains('txt') || fileType.contains('markdown')) {
      bg = const Color(0xFFFEF9C3);
      fg = const Color(0xFFCA8A04);
      label = 'MD';
      icon = Icons.notes_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: fg)),
        ],
      ),
    );
  }

  Widget _filterChip(String filterKey, String label) {
    final isSelected = _filter == filterKey;
    return InkWell(
      onTap: () => setState(() => _filter = filterKey),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E1B4B) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildReaderCanvas(Map<String, dynamic> sop, bool canManage) {
    final int id = sop['id'];
    final String title = sop['title'] ?? 'Standard Operating Procedure';
    final String author = sop['author'] ?? 'KGPL Technical Operations';
    final String date = sop['date'] ?? 'March 2025';
    final String version = sop['version'] ?? '1.0';
    final String courseTitle = sop['course_title'] ?? 'IT Infrastructure & Operations';
    final String moduleTitle = sop['module_title'] ?? 'Enterprise Linux & Networking';
    final bool isRead = sop['is_read'] == 1 || sop['is_read'] == true;
    final int sizeKb = sop['file_size_kb'] ?? 250;
    final String filePath = sop['file_path'] ?? '';
    final List<dynamic> steps = sop['steps'] is List ? sop['steps'] : [];
    final String markdown = sop['markdownContent'] ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          // Reader Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'KGPL-SOP-${id.toString().padLeft(3, '0')}',
                              style: const TextStyle(
                                fontFamily: 'Courier',
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: Color(0xFF4F46E5),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$courseTitle • $moduleTitle',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),

                // Download Button
                ElevatedButton.icon(
                  icon: const Icon(Icons.file_download_rounded, size: 16),
                  label: Text('Download File ($sizeKb KB)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _downloadSopFile(filePath, title),
                ),
                const SizedBox(width: 8),

                // Delete Button for TL
                if (canManage)
                  IconButton(
                    tooltip: 'Delete SOP Document',
                    icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
                    onPressed: () => _deleteSop(id),
                  ),

                const SizedBox(width: 8),

                // Compliance Button
                ElevatedButton.icon(
                  icon: Icon(isRead ? Icons.verified_rounded : Icons.check_circle_outline_rounded, size: 16),
                  label: Text(isRead ? 'Completed & Verified' : 'Mark as Read'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isRead ? AppTheme.success : const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isRead ? null : () => _markAsRead(id),
                ),
              ],
            ),
          ),

          // Reader Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Document Metadata Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _MetaPill(icon: Icons.person_rounded, label: 'Authors: $author'),
                        _MetaPill(icon: Icons.calendar_today_rounded, label: 'Date: $date'),
                        _MetaPill(icon: Icons.tag_rounded, label: 'Version: $version'),
                        const _MetaPill(icon: Icons.shield_rounded, label: 'Enterprise Standard'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Live inline preview of the attached file (PDF / Excel / Photo / Text)
                  _buildDocumentPreview(sop),

                  // Step-by-Step Procedure Workflow
                  if (steps.isNotEmpty) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.format_list_numbered_rounded, color: Color(0xFF6366F1), size: 18),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Step-by-Step Execution Sequence',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ...List.generate(steps.length, (idx) {
                      final stepText = steps[idx].toString();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 13,
                              backgroundColor: const Color(0xFF4F46E5),
                              child: Text(
                                '${idx + 1}',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: SelectableText(
                                stepText,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  height: 1.5,
                                  color: Color(0xFF1E293B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copy step text',
                              icon: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF64748B)),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: stepText));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Copied step to clipboard!'), duration: Duration(seconds: 1)),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 24),
                  ],

                  // Embedded Screenshots / Diagrams (for Zabbix & Metallic SOPs)
                  if (title.toLowerCase().contains('zabbix')) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.image_rounded, color: Color(0xFF0284C7), size: 18),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Verified Visual Runbook & Terminal Screens',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildScreenshotCard(
                      '${ApiConfig.serverOrigin}/uploads/sop_images/media_179421_image5.png',
                      'Figure 1: RHEL 9 nmtui Network Configuration for Static IP 192.168.1.165',
                    ),
                    const SizedBox(height: 14),
                    _buildScreenshotCard(
                      '${ApiConfig.serverOrigin}/uploads/sop_images/media_179421_image6.png',
                      'Figure 2: MySQL Server Installation on Red Hat Enterprise Linux 9',
                    ),
                    const SizedBox(height: 14),
                    _buildScreenshotCard(
                      '${ApiConfig.serverOrigin}/uploads/sop_images/media_179421_image10.png',
                      'Figure 3: Initial Database Schema Import & log_bin_trust_function_creators Configuration',
                    ),
                    const SizedBox(height: 14),
                    _buildScreenshotCard(
                      '${ApiConfig.serverOrigin}/uploads/sop_images/media_179421_image14.png',
                      'Figure 4: Zabbix Web Frontend Prerequisite Checks - All OK',
                    ),
                    const SizedBox(height: 14),
                    _buildScreenshotCard(
                      '${ApiConfig.serverOrigin}/uploads/sop_images/media_179421_image19.png',
                      'Figure 5: Zabbix 7.0 Production Monitoring Dashboard (http://192.168.1.165/zabbix)',
                    ),
                    const SizedBox(height: 28),
                  ] else if (title.toLowerCase().contains('metallic') || title.toLowerCase().contains('laptop')) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.image_rounded, color: Color(0xFF0284C7), size: 18),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Commvault Metallic Console Visual Workflow',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildScreenshotCard(
                      '${ApiConfig.serverOrigin}/uploads/sop_images/media_179421_image1.png',
                      'Figure 1: Commvault Metallic Navigation > Manage > Plans Overview',
                    ),
                    const SizedBox(height: 14),
                    _buildScreenshotCard(
                      '${ApiConfig.serverOrigin}/uploads/sop_images/media_179421_image2.png',
                      'Figure 2: Creating Laptop Plan from Plans Page',
                    ),
                    const SizedBox(height: 14),
                    _buildScreenshotCard(
                      '${ApiConfig.serverOrigin}/uploads/sop_images/media_179421_image8.png',
                      'Figure 3: Configuring Custom Path C:\\Users\\Administrator\\Documents & Filters',
                    ),
                    const SizedBox(height: 28),
                  ],

                  // Markdown or Full Documentation text
                  if (markdown.isNotEmpty) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.code_rounded, color: Color(0xFF10B981), size: 18),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Command Execution & Configuration Directives',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: SelectableText(
                        markdown,
                        style: const TextStyle(
                          color: Color(0xFFF8FAFC),
                          fontSize: 13,
                          height: 1.55,
                          fontFamily: 'Courier',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewSection({
    required IconData icon,
    required Color color,
    required String heading,
    required Widget child,
    String? chipLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                heading,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
            ),
            if (chipLabel != null && chipLabel.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withOpacity(0.35)),
                ),
                child: Text(
                  chipLabel.toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        child,
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildDocumentPreview(Map<String, dynamic> sop) {
    final String title = sop['title'] ?? 'SOP Document';
    final String filePath = (sop['file_path'] ?? '').toString();

    if (_previewLoading) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.symmetric(vertical: 44),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
            SizedBox(height: 12),
            Text('Loading document preview...', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ],
        ),
      );
    }

    final preview = _preview;
    if (preview == null) return const SizedBox.shrink();
    final String kind = (preview['kind'] ?? '').toString();
    final String ext = (preview['ext'] ?? '').toString();

    if (kind == 'image') {
      final String url = '${ApiConfig.serverOrigin}${preview['url']}';
      return _previewSection(
        icon: Icons.image_rounded,
        color: const Color(0xFF9333EA),
        heading: 'Attached Image — Visual SOP Reference',
        chipLabel: ext,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => _openLightbox(url, title),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 520),
                  child: Image.network(
                    url,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : Container(
                            height: 260,
                            alignment: Alignment.center,
                            color: const Color(0xFFF8FAFC),
                            child: const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
                          ),
                    errorBuilder: (_, __, ___) => Container(
                      height: 180,
                      color: const Color(0xFFF1F5F9),
                      alignment: Alignment.center,
                      child: const Text('Image could not be loaded', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.zoom_in_rounded, size: 15, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text('Click the image to zoom and inspect details', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                    ),
                    TextButton.icon(
                      onPressed: () => _openLightbox(url, title),
                      icon: const Icon(Icons.open_in_full_rounded, size: 15),
                      label: const Text('Full screen', style: TextStyle(fontSize: 11.5)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (kind == 'pdf') {
      final String rel = (preview['url'] ?? '').toString();
      final String url = rel.startsWith('http') ? rel : '${ApiConfig.serverOrigin}$rel';
      final String fileName = filePath.isNotEmpty ? filePath.split('/').last : 'SOP Document.pdf';
      return _previewSection(
        icon: Icons.picture_as_pdf_rounded,
        color: const Color(0xFFDC2626),
        heading: 'Attached PDF Document',
        chipLabel: ext,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: const Color(0xFFF8FAFC),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFDC2626), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fileName,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => openExternalUrl(url),
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: const Text('Open in new tab', style: TextStyle(fontSize: 11.5)),
                    ),
                  ],
                ),
              ),
              SopPdfEmbed(url: url, height: 620),
            ],
          ),
        ),
      );
    }

    if (kind == 'table') {
      final List<String> headers = ((preview['headers'] as List?) ?? []).map((e) => e.toString()).toList();
      final List<dynamic> rows = (preview['rows'] as List?) ?? [];
      return _previewSection(
        icon: Icons.table_chart_rounded,
        color: const Color(0xFF16A34A),
        heading: 'Spreadsheet Data Preview',
        chipLabel: ext,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 480),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 42,
                    dataRowMinHeight: 36,
                    dataRowMaxHeight: 52,
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFEEF2FF)),
                    columns: headers
                        .map((h) => DataColumn(
                              label: Text(h, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF312E81))),
                            ))
                        .toList(),
                    rows: rows.map((r) {
                      final List<dynamic> cells = r is List ? r : [r];
                      return DataRow(
                        cells: cells
                            .map((c) => DataCell(
                                  SizedBox(
                                    width: 170,
                                    child: Text(
                                      c.toString(),
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ))
                            .toList(),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${rows.length} rows × ${headers.length} columns • scroll to explore the full sheet',
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ),
      );
    }

    if (kind == 'text') {
      final String text = (preview['text'] ?? '').toString();
      return _previewSection(
        icon: Icons.notes_rounded,
        color: const Color(0xFFCA8A04),
        heading: 'Document Content',
        chipLabel: ext,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 520),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: 'Courier', fontSize: 12.5, height: 1.6, color: Color(0xFF1E293B)),
            ),
          ),
        ),
      );
    }

    // office (docx/doc) or missing attachment
    final bool missing = kind == 'missing';
    final String absUrl = filePath.startsWith('http') ? filePath : '${ApiConfig.serverOrigin}$filePath';
    return _previewSection(
      icon: missing ? Icons.link_off_rounded : Icons.description_rounded,
      color: const Color(0xFF0284C7),
      heading: missing ? 'Document Attachment' : 'Attached Office Document',
      chipLabel: ext,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Column(
          children: [
            Icon(missing ? Icons.link_off_rounded : Icons.article_rounded, size: 44, color: const Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            Text(
              missing
                  ? 'The attached file is not available on the server yet. The procedure details below are still fully readable.'
                  : 'This ${ext.isEmpty ? 'document' : ext.toUpperCase()} file opens in your system viewer. The full procedure is also rendered below.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.5),
            ),
            if (!missing && filePath.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => openExternalUrl(absUrl),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Open Document'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () => _downloadSopFile(filePath, title),
                    icon: const Icon(Icons.file_download_rounded, size: 16),
                    label: const Text('Download'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0284C7),
                      side: const BorderSide(color: Color(0xFF0284C7)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScreenshotCard(String url, String caption) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
            child: InkWell(
              onTap: () => _openLightbox(url, caption),
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  height: 160,
                  color: const Color(0xFFF1F5F9),
                  child: const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.image_outlined, color: Color(0xFF94A3B8)),
                        SizedBox(width: 8),
                        Text('Screenshot preview available in document attachment', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    caption,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: const Color(0xFF475569)),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// TEAM LEADER SOP UPLOAD MODAL (DEVICE FILE PICKER: PDF, EXCEL, PHOTO)
// -----------------------------------------------------------------------------
class _UploadSopDialog extends StatefulWidget {
  final VoidCallback onSuccess;

  const _UploadSopDialog({required this.onSuccess});

  @override
  State<_UploadSopDialog> createState() => _UploadSopDialogState();
}

class _UploadSopDialogState extends State<_UploadSopDialog> {
  final ApiService _api = ApiService();
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _summaryController = TextEditingController();
  final _versionController = TextEditingController(text: '1.0');
  final _markdownController = TextEditingController();

  String _selectedCategory = 'IT Infrastructure & Monitoring';
  String _fileType = 'sop';
  String? _pickedFileName;
  int? _pickedFileSizeKb;
  String? _base64File;
  bool _isSubmitting = false;

  final List<String> _categories = [
    'IT Infrastructure & Monitoring',
    'Data Protection & Backup',
    'Database & Infrastructure Operations',
    'Endpoint Security & Cloud Backup',
    'Enterprise Linux & Security Operations',
    'Software Architecture & API Standards',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _summaryController.dispose();
    _versionController.dispose();
    _markdownController.dispose();
    super.dispose();
  }

  Future<void> _pickFileFromDevice() async {
    try {
      final PickedFile? file = await pickDeviceFile(
        allowedExtensions: ['pdf', 'xlsx', 'xls', 'csv', 'png', 'jpg', 'jpeg', 'docx', 'doc', 'md'],
      );

      if (file != null) {
        final ext = file.extension;

        String detectedType = 'doc';
        if (ext == 'pdf') {
          detectedType = 'pdf';
        } else if (['xlsx', 'xls', 'csv'].contains(ext)) {
          detectedType = 'excel';
        } else if (['png', 'jpg', 'jpeg'].contains(ext)) {
          detectedType = 'photo';
        }

        setState(() {
          _pickedFileName = file.name;
          _pickedFileSizeKb = (file.size / 1024).round();
          _fileType = detectedType;
          if (file.bytes != null) {
            _base64File = base64Encode(file.bytes!);
          }
          if (_titleController.text.trim().isEmpty) {
            _titleController.text = file.name.replaceAll(RegExp(r'\.[^.]+$'), '').replaceAll('_', ' ');
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File selection error: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  Future<void> _submitUpload() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      await _api.post(ApiConfig.tlSops, {
        'title': _titleController.text.trim(),
        'category': _selectedCategory,
        'summary': _summaryController.text.trim(),
        'version': _versionController.text.trim(),
        'file_name': _pickedFileName,
        'file_data': _base64File,
        'file_type': _fileType,
        'markdown_content': _markdownController.text.trim(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ SOP document successfully uploaded from device and published!'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload SOP: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Container(
        width: 620,
        padding: const EdgeInsets.all(26),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFFA855F7)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Upload New SOP Document',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        Text(
                          'Add PDF, Excel sheet, Photo, or Markdown SOP directly from your device',
                          style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 16),

                // Title
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: 'SOP Document Title *',
                    hintText: 'e.g. Metallic Endpoint Silent Installation SOP',
                    prefixIcon: const Icon(Icons.title_rounded, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter SOP title' : null,
                ),

                const SizedBox(height: 14),

                // Category & Version
                Row(
                  children: [
                    Expanded(
                      flex: 65,
                      child: DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        decoration: InputDecoration(
                          labelText: 'Operational Category',
                          prefixIcon: const Icon(Icons.category_rounded, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12.5)))).toList(),
                        onChanged: (v) => setState(() => _selectedCategory = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 35,
                      child: TextFormField(
                        controller: _versionController,
                        decoration: InputDecoration(
                          labelText: 'Version',
                          hintText: '1.0',
                          prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Device File Attachment Box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFCBD5E1), style: BorderStyle.solid),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.attachment_rounded, size: 18, color: Color(0xFF6366F1)),
                          SizedBox(width: 8),
                          Text(
                            'Attach File From Device (PDF, Excel, Photo, Word)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Supports .pdf, .xlsx, .xls, .csv, .png, .jpg, .jpeg, .docx directly from your computer.',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 12),

                      if (_pickedFileName != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.insert_drive_file_rounded, color: Color(0xFF6366F1), size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_pickedFileName!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                    Text('$_pickedFileSizeKb KB • Type: ${_fileType.toUpperCase()}', style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.danger),
                                onPressed: () => setState(() {
                                  _pickedFileName = null;
                                  _pickedFileSizeKb = null;
                                  _base64File = null;
                                }),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Center(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.file_upload_outlined, size: 18),
                            label: const Text('Browse Device for SOP File'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF4F46E5),
                              side: const BorderSide(color: Color(0xFF6366F1)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            ),
                            onPressed: _pickFileFromDevice,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Markdown / Procedural Text
                TextFormField(
                  controller: _markdownController,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: 'Procedure Details / Markdown Instructions (Optional)',
                    hintText: 'Enter step-by-step instructions, command lines, or prerequisites...',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                const SizedBox(height: 22),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isSubmitting ? null : _submitUpload,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Publish SOP Document', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
