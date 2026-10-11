import 'package:flutter/material.dart';

import '../../services/api_service.dart';

const _red = Color(0xFFEF4444);
const _accent = Color(0xFF3355FF);

enum _RolesTab { assign, manage }

class AdminRolesScreen extends StatefulWidget {
  const AdminRolesScreen({super.key});

  @override
  State<AdminRolesScreen> createState() => _AdminRolesScreenState();
}

class _AdminRolesScreenState extends State<AdminRolesScreen> {
  _RolesTab _tab = _RolesTab.assign;
  List<Map<String, dynamic>> _users = [];
  bool _usersError = false;
  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _permissions = [];
  bool _loading = true;
  int? _busyUserId;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.get('/roles'),
        ApiService.get('/permissions'),
      ]);
      setState(() {
        _roles = (results[0] as List).cast<Map<String, dynamic>>();
        _permissions = (results[1] as List).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      _notify('Could not load roles data', isError: true);
    }

    try {
      final data = await ApiService.get('/users');
      setState(() {
        _users = (data as List).cast<Map<String, dynamic>>();
        _usersError = false;
      });
    } catch (e) {
      setState(() => _usersError = true);
    }

    setState(() => _loading = false);
  }

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _red : null,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }

  Future<void> _changeUserRole(Map<String, dynamic> user, int roleId) async {
    final userId = user['user_id'] is String
        ? int.parse(user['user_id'])
        : user['user_id'] as int;
    setState(() => _busyUserId = userId);
    try {
      await ApiService.patch('/users/$userId/role', {'role_id': roleId});
      setState(() {
        user['role_id'] = roleId;
      });
      _notify('Role updated');
    } on ApiException catch (e) {
      _notify(e.message, isError: true);
    } catch (e) {
      _notify(
        'Could not update role — endpoint may not exist yet',
        isError: true,
      );
    } finally {
      setState(() => _busyUserId = null);
    }
  }

  Future<void> _deleteRole(Map<String, dynamic> role) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete role?'),
        content: Text(
          'Delete role "${role['role_name']}"? This fails if any user still holds it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: _red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final roleId = role['role_id'] is String
        ? int.parse(role['role_id'])
        : role['role_id'] as int;
    try {
      await ApiService.delete('/roles/$roleId');
      _notify('Role deleted');
      _loadAll();
    } on ApiException catch (e) {
      _notify(e.message, isError: true);
    } catch (e) {
      _notify('Could not delete role', isError: true);
    }
  }

  Future<void> _openNewRoleSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewRoleSheet(),
    );
    if (created == true) {
      _notify('Role created');
      _loadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roles'),
        actions: _tab == _RolesTab.manage
            ? [
                IconButton(
                  onPressed: _openNewRoleSheet,
                  icon: const Icon(Icons.add),
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      _tabChip(colors, 'Assign roles', _RolesTab.assign),
                      _tabChip(colors, 'Roles & permissions', _RolesTab.manage),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_tab == _RolesTab.assign)
                  ..._buildAssign(colors)
                else
                  ..._buildManage(colors),
              ],
            ),
    );
  }

  Widget _tabChip(ColorScheme colors, String label, _RolesTab tab) {
    final selected = _tab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? colors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? colors.onSurface : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAssign(ColorScheme colors) {
    return [
      if (_usersError)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFD97706).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: Color(0xFFD97706),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'GET /users isn\'t implemented on the backend yet, so this list is empty.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                ),
              ),
            ],
          ),
        ),
      if (_users.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(
            child: Text(
              'No users to display.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
        )
      else
        for (final u in _users) _buildUserRow(colors, u),
    ];
  }

  Widget _buildUserRow(ColorScheme colors, Map<String, dynamic> u) {
    final userId = u['user_id'] is String
        ? int.parse(u['user_id'])
        : u['user_id'] as int;
    final roleId = u['role_id'] is String
        ? int.parse(u['role_id'])
        : u['role_id'] as int?;
    final busy = _busyUserId == userId;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: _accent,
            child: Text(
              (u['username'] as String? ?? '?').substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u['username'] as String? ?? '',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
                Text(
                  u['email'] as String? ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.onSurfaceVariant,
              ),
            )
          else
            DropdownButton<int>(
              value:
                  _roles.any(
                    (r) =>
                        (r['role_id'] is String
                            ? int.parse(r['role_id'])
                            : r['role_id']) ==
                        roleId,
                  )
                  ? roleId
                  : null,
              underline: const SizedBox.shrink(),
              items: _roles.map((r) {
                final id = r['role_id'] is String
                    ? int.parse(r['role_id'])
                    : r['role_id'] as int;
                return DropdownMenuItem(
                  value: id,
                  child: Text(
                    r['role_name'] as String? ?? '',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) _changeUserRole(u, v);
              },
            ),
        ],
      ),
    );
  }

  List<Widget> _buildManage(ColorScheme colors) {
    return [
      _sectionCard(
        colors,
        'Roles',
        _roles.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'No roles created yet.',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                ),
              ]
            : _roles.map((r) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r['role_name'] as String? ?? '',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                              ),
                            ),
                            if (r['description'] != null)
                              Text(
                                r['description'] as String,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _deleteRole(r),
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 17,
                          color: _red,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                );
              }).toList(),
      ),
      const SizedBox(height: 14),
      _sectionCard(
        colors,
        'Permissions',
        _permissions.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'No permissions defined yet.',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                ),
              ]
            : _permissions.map((p) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['permission_key'] as String? ?? '',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontFamily: 'monospace',
                          color: colors.onSurface,
                        ),
                      ),
                      if (p['description'] != null)
                        Text(
                          p['description'] as String,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
      ),
    ];
  }

  Widget _sectionCard(ColorScheme colors, String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          ...children,
        ],
      ),
    );
  }
}

class _NewRoleSheet extends StatefulWidget {
  const _NewRoleSheet();

  @override
  State<_NewRoleSheet> createState() => _NewRoleSheetState();
}

class _NewRoleSheetState extends State<_NewRoleSheet> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Role name is required');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiService.post('/roles', {
        'role_name': _nameController.text.trim(),
        if (_descriptionController.text.trim().isNotEmpty)
          'description': _descriptionController.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not create role');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colors.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Text(
              'New role',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: _decoration(
                colors,
                hint: 'Role name, e.g. kitchen_staff',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: _decoration(colors, hint: 'Description (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: _red, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.onSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: _submitting
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.surface,
                        ),
                      )
                    : Text(
                        'Create role',
                        style: TextStyle(
                          color: colors.surface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(ColorScheme colors, {String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: colors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent),
      ),
    );
  }
}
