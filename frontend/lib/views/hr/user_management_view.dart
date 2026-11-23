import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/device_file_picker.dart';
import '../../widgets/kgpl_brand_badge.dart';

class UserManagementView extends StatefulWidget {
  const UserManagementView({super.key});

  @override
  State<UserManagementView> createState() => _UserManagementViewState();
}

class _UserManagementViewState extends State<UserManagementView> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  bool _refreshing = false;
  String? _loadError;
  List<dynamic> _users = [];
  String _selectedRole = 'all';
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _listCtrl = ScrollController();
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsers({bool silent = false}) async {
    if (silent) {
      setState(() => _refreshing = true);
    } else {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final res = await _api.get(ApiConfig.hrUsers);
      if (!mounted) return;
      setState(() {
        _users = (res is Map ? res['users'] as List? : null) ?? [];
        _isLoading = false;
        _refreshing = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _refreshing = false;
        if (_users.isEmpty) _loadError = e.toString();
      });
      if (!silent) _showSnackbar(e.toString(), isError: true);
    }
  }

  int _idOf(dynamic u) => (u['id'] as num).toInt();

  bool _isActive(dynamic u) => u['is_active'] == 1 || u['is_active'] == true;

  List<dynamic> get _visibleUsers {
    final q = _searchQuery.toLowerCase();
    final filtered = _users.where((u) {
      if (_selectedRole != 'all' &&
          (u['role'] ?? '').toString() != _selectedRole) {
        return false;
      }
      if (q.isEmpty) return true;
      final haystack = [
        u['name'],
        u['email'],
        u['intern_code'],
        u['employee_code'],
        u['department_name'],
        u['assigned_team_leader_name'],
      ].whereType<Object>().join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();

    const order = {'hr_admin': 0, 'team_leader': 1, 'intern': 2};
    filtered.sort((a, b) {
      final ra = order[(a['role'] ?? '').toString()] ?? 3;
      final rb = order[(b['role'] ?? '').toString()] ?? 3;
      if (ra != rb) return ra.compareTo(rb);
      return (a['name'] ?? '').toString().toLowerCase().compareTo(
            (b['name'] ?? '').toString().toLowerCase(),
          );
    });
    return filtered;
  }

  Future<void> _toggleStatus(dynamic user) async {
    final id = _idOf(user);
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      final res = await _api.patch('${ApiConfig.hrUsers}/$id/toggle-status');
      final msg = (res is Map && res['message'] != null)
          ? res['message'].toString()
          : 'Account status updated.';
      _showSnackbar(msg);
      await _loadUsers(silent: true);
    } on ApiException catch (e) {
      _showSnackbar(e.message, isError: true);
    } catch (e) {
      _showSnackbar(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _openForm({dynamic existing}) async {
    final message = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UserFormDialog(api: _api, existing: existing),
    );
    if (!mounted || message == null) return;
    _showSnackbar(message);
    _loadUsers(silent: true);
  }

  Future<void> _resetPassword(dynamic user) async {
    final message = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ResetPasswordDialog(
        api: _api,
        userId: _idOf(user),
        userName: (user['name'] ?? 'this account').toString(),
      ),
    );
    if (!mounted || message == null) return;
    _showSnackbar(message);
  }

  Future<void> _confirmDelete(dynamic user) async {
    final message = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeleteUserDialog(
        api: _api,
        userId: _idOf(user),
        userName: (user['name'] ?? 'This account').toString(),
      ),
    );
    if (!mounted || message == null) return;
    _showSnackbar(message);
    _loadUsers(silent: true);
  }

  void _showAssignDialog({int? focusInternId}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AssignInternsDialog(
        api: _api,
        focusInternId: focusInternId,
        onAssigned: (message) {
          _showSnackbar(message);
          _loadUsers(silent: true);
        },
      ),
    );
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedRole = 'all';
    });
  }

  void _showSnackbar(String msg, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.primaryNavy,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color:
                  isError ? const Color(0xFFFCA5A5) : const Color(0xFF6EE7B7),
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

  @override
  Widget build(BuildContext context) {
    final visible = _visibleUsers;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KgplPageHeader(
            title: 'User Accounts',
            subtitle: 'Create, assign, and manage every portal account',
            icon: Icons.manage_accounts_outlined,
            actions: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withOpacity(0.35)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: const Icon(Icons.assignment_ind_outlined, size: 18),
                label: const Text('Assign Interns'),
                onPressed: () => _showAssignDialog(),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentGold,
                  foregroundColor: AppTheme.primaryNavy,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Create User'),
                onPressed: () => _openForm(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSummary(),
          const SizedBox(height: 16),
          _buildToolbar(visible),
          const SizedBox(height: 16),
          Expanded(child: _buildTableCard(visible)),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final interns = _users.where((u) => u['role'] == 'intern').toList();
    final leaders = _users.where((u) => u['role'] == 'team_leader').toList();
    final admins = _users.where((u) => u['role'] == 'hr_admin').toList();
    final cards = <Widget>[
      _SummaryCard(
        label: 'Total accounts',
        value: '${_users.length}',
        hint: '${_users.where(_isActive).length} active',
        icon: Icons.people_alt_outlined,
        color: AppTheme.primaryBlue,
      ),
      _SummaryCard(
        label: 'Interns',
        value: '${interns.length}',
        hint: '${interns.where(_isActive).length} active',
        icon: Icons.school_outlined,
        color: AppTheme.info,
      ),
      _SummaryCard(
        label: 'Team Leaders',
        value: '${leaders.length}',
        hint: '${leaders.where(_isActive).length} active',
        icon: Icons.supervisor_account_outlined,
        color: AppTheme.accentIndigo,
      ),
      _SummaryCard(
        label: 'HR Admins',
        value: '${admins.length}',
        hint: '${admins.where(_isActive).length} active',
        icon: Icons.admin_panel_settings_outlined,
        color: AppTheme.warning,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          final cardWidth = (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final card in cards) SizedBox(width: cardWidth, child: card),
            ],
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

  Widget _buildToolbar(List<dynamic> visible) {
    final search = SizedBox(
      height: 44,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, size: 20),
          hintText: 'Search name, email, code, department, or team leader',
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
    );

    final filters = SegmentedButton<String>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ),
      segments: const [
        ButtonSegment(value: 'all', label: Text('All')),
        ButtonSegment(value: 'intern', label: Text('Interns')),
        ButtonSegment(value: 'team_leader', label: Text('Team Leaders')),
        ButtonSegment(value: 'hr_admin', label: Text('HR Admins')),
      ],
      selected: {_selectedRole},
      onSelectionChanged: (val) => setState(() => _selectedRole = val.first),
    );

    final refresh = IconButton(
      tooltip: 'Refresh accounts',
      onPressed: _refreshing ? null : () => _loadUsers(silent: true),
      icon: _refreshing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh, size: 20),
      style: IconButton.styleFrom(
        foregroundColor: AppTheme.textSecondary,
        backgroundColor: Colors.white,
        side: const BorderSide(color: AppTheme.borderColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        minimumSize: const Size(44, 44),
        maximumSize: const Size(44, 44),
        padding: EdgeInsets.zero,
      ),
    );

    final filtered = _selectedRole != 'all' || _searchQuery.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 880) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 10),
                  refresh,
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: filters,
                    ),
                  ),
                  if (filtered) ...[
                    const SizedBox(width: 10),
                    Text(
                      '${visible.length} of ${_users.length}',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 12),
            filters,
            if (filtered) ...[
              const SizedBox(width: 12),
              Text(
                '${visible.length} of ${_users.length}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
            const SizedBox(width: 10),
            refresh,
          ],
        );
      },
    );
  }

  Widget _buildTableCard(List<dynamic> visible) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final showLeaders = width >= 900;
          final showCode = width >= 1040;
          return Column(
            children: [
              if (_refreshing)
                const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: AppTheme.primaryBlue,
                ),
              _buildTableHeader(showLeaders, showCode),
              const Divider(height: 1, color: AppTheme.borderColor),
              Expanded(
                child: _buildTableBody(visible, showLeaders, showCode),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTableHeader(bool showLeaders, bool showCode) {
    const headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppTheme.textSecondary,
      letterSpacing: 0.4,
    );
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          const Expanded(
            flex: 30,
            child: Text('ACCOUNT',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: headerStyle),
          ),
          const Expanded(
            flex: 13,
            child: Text('ROLE',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: headerStyle),
          ),
          const Expanded(
            flex: 22,
            child: Text('DEPARTMENT',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: headerStyle),
          ),
          if (showLeaders)
            const Expanded(
              flex: 17,
              child: Text('TEAM LEADER',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: headerStyle),
            ),
          if (showCode)
            const Expanded(
              flex: 12,
              child: Text('CODE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: headerStyle),
            ),
          const Expanded(
            flex: 14,
            child: Text('STATUS',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: headerStyle),
          ),
          const SizedBox(
            width: 152,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('ACTIONS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: headerStyle),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableBody(
      List<dynamic> visible, bool showLeaders, bool showCode) {
    if (_isLoading && _users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _users.isEmpty) {
      return _ErrorState(message: _loadError!, onRetry: () => _loadUsers());
    }
    if (visible.isEmpty) {
      final filtered = _selectedRole != 'all' || _searchQuery.isNotEmpty;
      return _EmptyAccounts(
        filtered: filtered,
        onClear: _clearFilters,
        onCreate: () => _openForm(),
      );
    }
    return Scrollbar(
      controller: _listCtrl,
      thumbVisibility: true,
      child: ListView.separated(
        controller: _listCtrl,
        padding: EdgeInsets.zero,
        itemCount: visible.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: AppTheme.borderColor),
        itemBuilder: (context, index) {
          final user = visible[index];
          return _HoverRow(
            baseColor: index.isEven ? Colors.white : const Color(0xFFFCFDFF),
            child:
                _buildRow(user, showLeaders: showLeaders, showCode: showCode),
          );
        },
      ),
    );
  }

  Widget _buildRow(dynamic user,
      {required bool showLeaders, required bool showCode}) {
    final role = (user['role'] ?? 'intern').toString();
    final meta = _roleMeta(role);
    final name = (user['name'] ?? '').toString();
    final email = (user['email'] ?? '').toString();
    final department = (user['department_name'] ?? '').toString();
    final code =
        (user['intern_code'] ?? user['employee_code'] ?? '').toString();
    final leader = (user['assigned_team_leader_name'] ?? '').toString();
    final contact = (user['contact_number'] ?? '').toString();
    final photoPath = (user['profile_photo_path'] ?? '').toString();

    final avatarFallback = Center(
      child: Text(
        _initials(name),
        style: TextStyle(
          color: meta.fg,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 30,
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: meta.bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: photoPath.isEmpty
                      ? avatarFallback
                      : Image.network(
                          '${ApiConfig.serverOrigin}$photoPath',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => avatarFallback,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      if (contact.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          contact,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 13,
            child:
                Align(alignment: Alignment.centerLeft, child: _roleBadge(role)),
          ),
          Expanded(
            flex: 22,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                department.isEmpty ? 'Not set' : department,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: department.isEmpty
                      ? AppTheme.textMuted
                      : AppTheme.textPrimary,
                ),
              ),
            ),
          ),
          if (showLeaders)
            Expanded(
              flex: 17,
              child: role == 'intern'
                  ? (leader.isEmpty
                      ? const Text(
                          'Unassigned',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      : Row(
                          children: [
                            const Icon(
                              Icons.person_outline,
                              size: 14,
                              color: AppTheme.primaryBlue,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                leader,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ))
                  : const Text('—',
                      style: TextStyle(color: AppTheme.textMuted)),
            ),
          if (showCode)
            Expanded(
              flex: 12,
              child: Text(
                code.isEmpty ? '—' : code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                  color: code.isEmpty
                      ? AppTheme.textMuted
                      : AppTheme.textSecondary,
                ),
              ),
            ),
          Expanded(
            flex: 14,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _statusPill(user),
            ),
          ),
          SizedBox(width: 152, child: _buildActions(user)),
        ],
      ),
    );
  }

  Widget _buildActions(dynamic user) {
    final id = _idOf(user);
    final role = (user['role'] ?? 'intern').toString();
    if (_busy.contains(id)) {
      return const Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: EdgeInsets.only(right: 8),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (role == 'intern')
          _actionButton(
            icon: Icons.assignment_ind_outlined,
            color: AppTheme.primaryBlue,
            tooltip: 'Assign team leader',
            onTap: () => _showAssignDialog(focusInternId: id),
          ),
        _actionButton(
          icon: Icons.edit_outlined,
          color: AppTheme.textSecondary,
          tooltip: 'Edit account',
          onTap: () => _openForm(existing: user),
        ),
        _actionButton(
          icon: Icons.key,
          color: AppTheme.primaryNavy,
          tooltip: 'Reset password',
          onTap: () => _resetPassword(user),
        ),
        if (id != 1)
          _actionButton(
            icon: Icons.delete_outline_rounded,
            color: AppTheme.danger,
            tooltip: 'Delete account',
            onTap: () => _confirmDelete(user),
          )
        else
          const SizedBox(width: 36),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        style: IconButton.styleFrom(
          foregroundColor: color,
          backgroundColor: color.withOpacity(0.08),
          minimumSize: const Size(32, 32),
          maximumSize: const Size(32, 32),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _roleBadge(String role) {
    final meta = _roleMeta(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: meta.bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: meta.fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            meta.label,
            style: TextStyle(
              color: meta.fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(dynamic user) {
    final active = _isActive(user);
    final busy = _busy.contains(_idOf(user));
    final color = active ? AppTheme.success : AppTheme.danger;
    return Tooltip(
      message: active ? 'Deactivate this account' : 'Activate this account',
      child: InkWell(
        onTap: busy ? null : () => _toggleStatus(user),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: busy
                ? const Color(0xFFF1F5F9)
                : (active ? AppTheme.successLight : AppTheme.dangerLight),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 10,
                  height: 10,
                  child:
                      CircularProgressIndicator(strokeWidth: 1.6, color: color),
                )
              else
                Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              const SizedBox(width: 6),
              Text(
                active ? 'Active' : 'Inactive',
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SHARED PIECES
// -----------------------------------------------------------------------------
class _RoleMeta {
  final String label;
  final Color bg;
  final Color fg;
  const _RoleMeta(this.label, this.bg, this.fg);
}

_RoleMeta _roleMeta(String role) {
  switch (role) {
    case 'team_leader':
      return const _RoleMeta(
          'Team Leader', Color(0xFFFEF3C7), Color(0xFFB45309));
    case 'hr_admin':
      return const _RoleMeta('HR Admin', Color(0xFFDBEAFE), Color(0xFF1E40AF));
    default:
      return const _RoleMeta('Intern', Color(0xFFE0F2FE), Color(0xFF0369A1));
  }
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

String _initials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

String? _dateOnly(dynamic value) {
  final raw = value?.toString() ?? '';
  if (raw.isEmpty || raw == 'null') return null;
  return raw.length >= 10 ? raw.substring(0, 10) : raw;
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        hint,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HoverRow extends StatefulWidget {
  final Widget child;
  final Color baseColor;

  const _HoverRow({required this.child, required this.baseColor});

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        color: _hover ? const Color(0xFFF1F5F9) : widget.baseColor,
        child: widget.child,
      ),
    );
  }
}

class _EmptyAccounts extends StatelessWidget {
  final bool filtered;
  final VoidCallback onClear;
  final VoidCallback onCreate;

  const _EmptyAccounts({
    required this.filtered,
    required this.onClear,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.infoLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              filtered ? Icons.search_off_rounded : Icons.group_add_outlined,
              color: AppTheme.info,
              size: 26,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            filtered ? 'No accounts match these filters' : 'No accounts yet',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            filtered
                ? 'Try a different search or role.'
                : 'Create the first account to start building the portal.',
            style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 16),
          if (filtered)
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
              label: const Text('Clear filters'),
            )
          else
            ElevatedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.person_add_alt_1, size: 17),
              label: const Text('Create User'),
            ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 34, color: AppTheme.textMuted),
          const SizedBox(height: 12),
          const Text(
            'Accounts could not be loaded',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 17),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;

  const _InlineError(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.dangerLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.danger.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppTheme.danger, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogTitle extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;

  const _DialogTitle(
      {required this.icon, required this.color, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// RESET PASSWORD
// -----------------------------------------------------------------------------
class _ResetPasswordDialog extends StatefulWidget {
  final ApiService api;
  final int userId;
  final String userName;

  const _ResetPasswordDialog({
    required this.api,
    required this.userId,
    required this.userName,
  });

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _controller = TextEditingController(text: 'Password@123');
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _controller.text;
    final validPolicy = password.length >= 8 &&
        RegExp(r'[A-Za-z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password);
    if (!validPolicy) {
      setState(() => _error =
          'Use at least 8 characters with both letters and numbers.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await widget.api.post(
        '${ApiConfig.hrUsers}/${widget.userId}/reset-password',
        {'new_password': password},
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        (res is Map && res['message'] != null)
            ? res['message'].toString()
            : 'Password updated.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const _DialogTitle(
        icon: Icons.key,
        color: AppTheme.primaryNavy,
        title: 'Reset password',
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set a temporary password for ${widget.userName}. Share it with them after saving.',
              style: const TextStyle(
                  fontSize: 12.5, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              obscureText: _obscure,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'New password',
                prefixIcon: const Icon(Icons.lock_outline, size: 19),
                helperText: 'At least 8 characters, letters and numbers',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 19,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _InlineError(_error!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save password'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// DELETE ACCOUNT
// -----------------------------------------------------------------------------
class _DeleteUserDialog extends StatefulWidget {
  final ApiService api;
  final int userId;
  final String userName;

  const _DeleteUserDialog({
    required this.api,
    required this.userId,
    required this.userName,
  });

  @override
  State<_DeleteUserDialog> createState() => _DeleteUserDialogState();
}

class _DeleteUserDialogState extends State<_DeleteUserDialog> {
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res =
          await widget.api.delete('${ApiConfig.hrUsers}/${widget.userId}');
      if (!mounted) return;
      Navigator.pop(
        context,
        (res is Map && res['message'] != null)
            ? res['message'].toString()
            : 'Account deleted.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const _DialogTitle(
        icon: Icons.warning_amber_rounded,
        color: AppTheme.danger,
        title: 'Delete account?',
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.userName} will be removed from the portal and will no longer be able to sign in. This cannot be undone.',
              style: const TextStyle(
                  fontSize: 12.5, color: AppTheme.textSecondary),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _InlineError(_error!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.danger,
            foregroundColor: Colors.white,
          ),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Delete account'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// CREATE / EDIT ACCOUNT
// -----------------------------------------------------------------------------
class _UserFormDialog extends StatefulWidget {
  final ApiService api;
  final dynamic existing;

  const _UserFormDialog({required this.api, this.existing});

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  final _passwordCtrl = TextEditingController(text: 'Password@123');
  final _codeCtrl = TextEditingController();
  final _collegeCtrl = TextEditingController();
  final _designationCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  String _role = 'intern';
  int? _departmentId;
  int? _leaderId;
  bool _obscure = true;
  bool _loadingOptions = true;
  bool _optionsFailed = false;
  bool _submitting = false;
  bool _removePhoto = false;
  Uint8List? _photoBytes;
  String? _photoBase64;
  String? _error;
  List<dynamic> _departments = [];
  List<dynamic> _leaders = [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _role = (existing['role'] ?? 'intern').toString();
      _nameCtrl =
          TextEditingController(text: (existing['name'] ?? '').toString());
      _emailCtrl =
          TextEditingController(text: (existing['email'] ?? '').toString());
      _departmentId = _asInt(existing['department_id']);
      _leaderId = _asInt(existing['assigned_team_leader_id']);
      _codeCtrl.text = (existing['intern_code'] ?? '').toString();
      _collegeCtrl.text = (existing['college_name'] ?? '').toString();
      _designationCtrl.text = (existing['designation'] ?? '').toString();
      _contactCtrl.text = (existing['contact_number'] ?? '').toString();
      _addressCtrl.text = (existing['address'] ?? '').toString();
    } else {
      _nameCtrl = TextEditingController();
      _emailCtrl = TextEditingController();
    }
    _loadOptions();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    _collegeCtrl.dispose();
    _designationCtrl.dispose();
    _contactCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final results = await Future.wait<dynamic>([
        widget.api.get(ApiConfig.hrDepartments),
        widget.api.get('${ApiConfig.hrUsers}?role=team_leader'),
      ]);
      if (!mounted) return;
      setState(() {
        _departments =
            (results[0] is Map ? results[0]['departments'] as List? : null) ??
                [];
        _leaders =
            (results[1] is Map ? results[1]['users'] as List? : null) ?? [];
        _loadingOptions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingOptions = false;
        _optionsFailed = true;
      });
    }
  }

  void _fail(String message) {
    setState(() => _error = message);
  }

  Future<void> _pickPhoto() async {
    final file = await pickDeviceFile(
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp']);
    if (file == null || file.bytes == null) return;
    if (file.bytes!.length > 2 * 1024 * 1024) {
      setState(() => _error = 'Choose an image smaller than 2 MB.');
      return;
    }
    final ext = file.name.split('.').last.toLowerCase();
    final mime = ext == 'jpg' || ext == 'jpeg' ? 'jpeg' : ext;
    setState(() {
      _photoBytes = file.bytes;
      _photoBase64 = 'data:image/$mime;base64,${base64Encode(file.bytes!)}';
      _removePhoto = false;
      _error = null;
    });
  }

  void _clearPhoto() {
    setState(() {
      _photoBytes = null;
      _photoBase64 = null;
      _removePhoto = true;
    });
  }

  Widget _photoPicker() {
    final existingPath =
        (widget.existing?['profile_photo_path'] ?? '').toString();
    ImageProvider? image;
    if (_photoBytes != null) {
      image = MemoryImage(_photoBytes!);
    } else if (!_removePhoto && existingPath.isNotEmpty) {
      image = NetworkImage('${ApiConfig.serverOrigin}$existingPath');
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
            foregroundImage: image,
            onForegroundImageError: image == null ? null : (_, __) {},
            child: const Icon(Icons.person_outline,
                size: 26, color: AppTheme.primaryBlue),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  image == null ? 'No photo added' : 'Profile photo ready',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                const Text(
                  'JPG, PNG or WEBP up to 2 MB',
                  style:
                      TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _submitting ? null : _pickPhoto,
            icon: const Icon(Icons.upload_outlined, size: 16),
            label: Text(image == null ? 'Upload' : 'Change'),
          ),
          if (image != null)
            IconButton(
              tooltip: 'Remove photo',
              onPressed: _submitting ? null : _clearPhoto,
              icon: const Icon(Icons.delete_outline, size: 18),
              color: AppTheme.danger,
            ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (name.isEmpty) {
      _fail('Enter the full name.');
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _fail('Enter a valid email address.');
      return;
    }
    if (!_isEdit) {
      final password = _passwordCtrl.text;
      final validPolicy = password.length >= 8 &&
          RegExp(r'[A-Za-z]').hasMatch(password) &&
          RegExp(r'[0-9]').hasMatch(password);
      if (!validPolicy) {
        _fail('Use at least 8 characters with both letters and numbers.');
        return;
      }
    }
    if (_role != 'hr_admin' && _departmentId == null) {
      _fail('Select a department.');
      return;
    }

    final body = <String, dynamic>{
      'name': name,
      'email': email,
      'contact_number': _contactCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
    };
    if (_photoBase64 != null) {
      body['profile_photo'] = _photoBase64;
    } else if (_removePhoto && _isEdit) {
      body['remove_photo'] = true;
    }
    if (!_isEdit) {
      body['password'] = _passwordCtrl.text;
      body['role'] = _role;
    }
    if (_role == 'intern') {
      body['department_id'] = _departmentId;
      body['assigned_team_leader_id'] = _leaderId;
      body['college_name'] = _collegeCtrl.text.trim();
      if (!_isEdit) {
        final code = _codeCtrl.text.trim();
        if (code.isNotEmpty) body['intern_code'] = code;
      } else {
        body['internship_start_date'] =
            _dateOnly(widget.existing['internship_start_date']);
        body['internship_end_date'] =
            _dateOnly(widget.existing['internship_end_date']);
      }
    } else if (_role == 'team_leader') {
      body['department_id'] = _departmentId;
      body['designation'] = _designationCtrl.text.trim().isEmpty
          ? 'Team Leader'
          : _designationCtrl.text.trim();
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = _isEdit
          ? await widget.api
              .put('${ApiConfig.hrUsers}/${widget.existing['id']}', body)
          : await widget.api.post(ApiConfig.hrUsers, body);
      if (!mounted) return;
      Navigator.pop(
        context,
        (res is Map && res['message'] != null)
            ? res['message'].toString()
            : (_isEdit ? 'Account updated.' : 'Account created.'),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  Widget _spaced(Widget child) {
    return Padding(padding: const EdgeInsets.only(top: 14), child: child);
  }

  Widget _twoUp(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }

  Widget _roleChip(String value, String label, IconData icon) {
    final selected = _role == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppTheme.textSecondary,
        ),
      ),
      avatar: Icon(icon,
          size: 16, color: selected ? Colors.white : AppTheme.textMuted),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppTheme.primaryNavy,
      backgroundColor: const Color(0xFFF8FAFC),
      side: BorderSide(
        color: selected ? AppTheme.primaryNavy : AppTheme.borderColor,
      ),
      onSelected: _submitting
          ? null
          : (_) => setState(() {
                _role = value;
                _error = null;
              }),
    );
  }

  Widget _mutedNote(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
      ),
    );
  }

  Widget _optionsBlock() {
    if (_loadingOptions) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_optionsFailed) {
      return _mutedNote(
        'Department and team leader lists could not be loaded. You can still save this account.',
      );
    }

    final departmentValue =
        _departments.any((d) => _asInt(d['id']) == _departmentId)
            ? _departmentId
            : null;
    final leaderValue =
        _leaders.any((l) => _asInt(l['id']) == _leaderId) ? _leaderId : null;

    final departmentField = _departments.isEmpty
        ? const InputDecorator(
            decoration: InputDecoration(
              labelText: 'Department *',
              prefixIcon: Icon(Icons.apartment_outlined, size: 19),
            ),
            child: Text(
              'No departments yet',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
          )
        : DropdownButtonFormField<int?>(
            value: departmentValue,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Department *',
              hintText: 'Select department',
              prefixIcon: Icon(Icons.apartment_outlined, size: 19),
            ),
            items: [
              ..._departments.map(
                (d) => DropdownMenuItem<int?>(
                  value: _asInt(d['id']),
                  child: Text(
                    (d['name'] ?? 'Department').toString(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: _submitting
                ? null
                : (val) => setState(() => _departmentId = val),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        departmentField,
        if (_role == 'intern') ...[
          _spaced(
            DropdownButtonFormField<int?>(
              value: leaderValue,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Team Leader',
                prefixIcon: Icon(Icons.person_outline, size: 19),
              ),
              items: [
                const DropdownMenuItem<int?>(
                    value: null, child: Text('Unassigned')),
                ..._leaders.map(
                  (l) => DropdownMenuItem<int?>(
                    value: _asInt(l['id']),
                    child: Text(
                      (l['name'] ?? 'Team Leader').toString(),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged:
                  _submitting ? null : (val) => setState(() => _leaderId = val),
            ),
          ),
          if (_leaders.isEmpty)
            _mutedNote('No team leaders yet. You can assign one later.'),
        ],
        if (_role == 'team_leader')
          _spaced(
            TextField(
              controller: _designationCtrl,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'Designation',
                hintText: 'e.g. Team Leader',
                prefixIcon: Icon(Icons.badge_outlined, size: 19),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEdit ? 'Edit account' : 'Create account';
    final meta = _roleMeta(_role);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: _DialogTitle(
        icon: _isEdit ? Icons.edit_outlined : Icons.person_add_alt_1,
        color: AppTheme.primaryBlue,
        title: title,
      ),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.58,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isEdit)
                  Row(
                    children: [
                      const Text(
                        'Account type',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: meta.bg,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          meta.label,
                          style: TextStyle(
                            color: meta.fg,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _roleChip('intern', 'Intern', Icons.school_outlined),
                      _roleChip('team_leader', 'Team Leader',
                          Icons.supervisor_account_outlined),
                      _roleChip('hr_admin', 'HR Admin',
                          Icons.admin_panel_settings_outlined),
                    ],
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _InlineError(_error!),
                ],
                _photoPicker(),
                _spaced(
                  _twoUp(
                    TextField(
                      controller: _nameCtrl,
                      enabled: !_submitting,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        prefixIcon: Icon(Icons.person_outline, size: 19),
                      ),
                    ),
                    TextField(
                      controller: _emailCtrl,
                      enabled: !_submitting,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.mail_outline, size: 19),
                      ),
                    ),
                  ),
                ),
                _spaced(
                  _twoUp(
                    TextField(
                      controller: _contactCtrl,
                      enabled: !_submitting,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Contact number',
                        hintText: '+91 98765 43210',
                        prefixIcon: Icon(Icons.call_outlined, size: 19),
                      ),
                    ),
                    TextField(
                      controller: _addressCtrl,
                      enabled: !_submitting,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        prefixIcon: Icon(Icons.home_outlined, size: 19),
                      ),
                    ),
                  ),
                ),
                if (!_isEdit)
                  _spaced(
                    TextField(
                      controller: _passwordCtrl,
                      enabled: !_submitting,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Initial password',
                        helperText:
                            'At least 8 characters with letters and numbers.',
                        prefixIcon: const Icon(Icons.lock_outline, size: 19),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 19,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                  ),
                if (_role == 'intern' || _role == 'team_leader')
                  _spaced(_optionsBlock()),
                if (_role == 'intern')
                  _spaced(
                    _twoUp(
                      TextField(
                        controller: _codeCtrl,
                        enabled: !_submitting && !_isEdit,
                        decoration: const InputDecoration(
                          labelText: 'Intern code',
                          hintText: 'Auto-generated if empty',
                          prefixIcon: Icon(Icons.tag, size: 19),
                        ),
                      ),
                      TextField(
                        controller: _collegeCtrl,
                        enabled: !_submitting,
                        decoration: const InputDecoration(
                          labelText: 'College / University',
                          prefixIcon: Icon(Icons.school_outlined, size: 19),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(_isEdit ? 'Save changes' : 'Create account'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// ASSIGN INTERNS
// -----------------------------------------------------------------------------
class _AssignInternsDialog extends StatefulWidget {
  final ApiService api;
  final int? focusInternId;
  final void Function(String message) onAssigned;

  const _AssignInternsDialog({
    required this.api,
    required this.onAssigned,
    this.focusInternId,
  });

  @override
  State<_AssignInternsDialog> createState() => _AssignInternsDialogState();
}

class _AssignInternsDialogState extends State<_AssignInternsDialog> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<dynamic> _tls = [];
  List<dynamic> _interns = [];
  int? _selectedTl;
  final Set<int> _selected = {};
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    if (widget.focusInternId != null) _selected.add(widget.focusInternId!);
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.get('${ApiConfig.hrUsers}?role=team_leader'),
        widget.api.get('${ApiConfig.hrUsers}?role=intern'),
      ]);
      final tls = ((results[0]['users'] as List?) ?? [])
          .where((u) => u['is_active'] == 1 || u['is_active'] == true)
          .toList();
      final interns = ((results[1]['users'] as List?) ?? [])
          .where((u) => u['is_active'] == 1 || u['is_active'] == true)
          .toList();
      if (!mounted) return;
      setState(() {
        _tls = tls;
        _interns = interns;
        _loading = false;
        _selected.removeWhere(
          (id) => !interns.any((i) => (i['id'] as num).toInt() == id),
        );
        if (_selectedTl == null) {
          String? currentLeaderName;
          if (widget.focusInternId != null) {
            for (final i in interns) {
              if ((i['id'] as num).toInt() == widget.focusInternId) {
                currentLeaderName =
                    (i['assigned_team_leader_name'] ?? '').toString();
                break;
              }
            }
          }
          for (final t in tls) {
            final id = (t['id'] as num).toInt();
            final name = (t['name'] ?? '').toString();
            if (currentLeaderName != null && name == currentLeaderName) {
              _selectedTl = id;
              break;
            }
          }
          _selectedTl ??= tls.length == 1 ? (tls.first['id'] as num).toInt() : null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException
            ? e.message
            : 'Could not load team leaders and interns.';
      });
    }
  }

  List<dynamic> get _filtered {
    if (_search.isEmpty) return _interns;
    final q = _search.toLowerCase();
    return _interns.where((i) {
      final name = (i['name'] ?? '').toString().toLowerCase();
      final code = (i['intern_code'] ?? '').toString().toLowerCase();
      final email = (i['email'] ?? '').toString().toLowerCase();
      return name.contains(q) || code.contains(q) || email.contains(q);
    }).toList();
  }

  Future<void> _submit() async {
    if (_selectedTl == null) {
      setState(() => _error = 'Choose a team leader first.');
      return;
    }
    if (_selected.isEmpty) {
      setState(() => _error = 'Select at least one intern to assign.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await widget.api.post(ApiConfig.hrAssignInterns, {
        'team_leader_id': _selectedTl,
        'intern_ids': _selected.toList(),
      });
      if (!mounted) return;
      final msg = (res is Map && res['message'] != null)
          ? res['message'].toString()
          : 'Interns assigned successfully';
      Navigator.pop(context);
      widget.onAssigned(msg);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is ApiException
            ? e.message
            : 'Could not assign interns. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final canSubmit = !_submitting &&
        !_loading &&
        _selectedTl != null &&
        _selected.isNotEmpty;
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = (screen.width - 80).clamp(320.0, 620.0).toDouble();
    final dialogHeight = (screen.height - 260).clamp(320.0, 540.0).toDouble();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.assignment_ind,
                color: AppTheme.primaryBlue, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Assign Interns to Team Leader',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerLight,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: AppTheme.danger.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppTheme.danger, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                  color: AppTheme.danger, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Team leader picker
                  DropdownButtonFormField<int>(
                    value: _selectedTl,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Team Leader *',
                      prefixIcon: Icon(Icons.person_outline, size: 20),
                    ),
                    hint: const Text('Select a team leader'),
                    items: _tls
                        .map((t) => DropdownMenuItem<int>(
                              value: (t['id'] as num).toInt(),
                              child: Text(
                                '${t['name'] ?? 'Team Leader'}${(t['employee_code'] ?? '').toString().isNotEmpty ? '  ·  ${t['employee_code']}' : ''}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: _submitting
                        ? null
                        : (v) => setState(() => _selectedTl = v),
                  ),
                  if (_tls.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'No active team leaders found. Create a team leader account first.',
                        style: TextStyle(color: AppTheme.warning, fontSize: 12),
                      ),
                    )
                  else if (_selectedTl == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Pick a team leader to enable assigning.',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                      ),
                    ),

                  const SizedBox(height: 18),

                  // Interns selection header
                  Row(
                    children: [
                      const Text(
                        'Select Interns',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.infoLight,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_selected.length} selected',
                          style: const TextStyle(
                            color: AppTheme.info,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _submitting || filtered.isEmpty
                            ? null
                            : () => setState(() {
                                  for (final i in filtered) {
                                    _selected.add((i['id'] as num).toInt());
                                  }
                                }),
                        child: const Text('Select all',
                            style: TextStyle(fontSize: 12)),
                      ),
                      TextButton(
                        onPressed: _submitting || _selected.isEmpty
                            ? null
                            : () => setState(() => _selected.clear()),
                        child:
                            const Text('Clear', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Search interns
                  SizedBox(
                    height: 42,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _search = v.trim()),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, size: 18),
                        hintText: 'Search interns by name, code, or email...',
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _search = '');
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Intern list
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.borderColor),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                _interns.isEmpty
                                    ? 'No active interns available.'
                                    : 'No interns match your search.',
                                style:
                                    const TextStyle(color: AppTheme.textMuted),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (ctx, idx) {
                                final i = filtered[idx];
                                final id = (i['id'] as num).toInt();
                                final checked = _selected.contains(id);
                                final name = (i['name'] ?? '').toString();
                                final code =
                                    (i['intern_code'] ?? '').toString();
                                final curTl =
                                    (i['assigned_team_leader_name'] ?? '')
                                        .toString();
                                final initial = name.trim().isNotEmpty
                                    ? name.trim()[0].toUpperCase()
                                    : '?';
                                return CheckboxListTile(
                                  value: checked,
                                  onChanged: _submitting
                                      ? null
                                      : (v) => setState(() {
                                            if (v == true) {
                                              _selected.add(id);
                                            } else {
                                              _selected.remove(id);
                                            }
                                          }),
                                  dense: true,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  activeColor: AppTheme.primaryBlue,
                                  secondary: CircleAvatar(
                                    radius: 16,
                                    backgroundColor:
                                        AppTheme.primaryBlue.withOpacity(0.12),
                                    child: Text(
                                      initial,
                                      style: const TextStyle(
                                        color: AppTheme.primaryBlue,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${code.isNotEmpty ? '$code  ·  ' : ''}${curTl.isNotEmpty ? 'Currently: $curTl' : 'Unassigned'}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: curTl.isNotEmpty
                                          ? AppTheme.textSecondary
                                          : AppTheme.textMuted,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Selected interns will be assigned to the chosen team leader and appear in their monitoring dashboard.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: canSubmit ? _submit : null,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.assignment_turned_in, size: 18),
          label: Text(
            _submitting
                ? 'Assigning…'
                : _selected.isEmpty
                    ? 'Assign Interns'
                    : 'Assign ${_selected.length} Intern${_selected.length == 1 ? '' : 's'}',
          ),
        ),
      ],
    );
  }
}
