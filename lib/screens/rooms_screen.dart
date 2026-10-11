import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/resident.dart';
import '../models/room.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

const _amber = Color(0xFFD97706);
const _green = Color(0xFF10B981);
const _red = Color(0xFFEF4444);

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  List<Room> _rooms = [];
  List<Resident> _residents = [];
  bool _loading = true;
  int? _busyResidentId;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.get('/rooms'),
        ApiService.get('/residents'),
      ]);
      setState(() {
        _rooms = (results[0] as List)
            .map((j) => Room.fromJson(j as Map<String, dynamic>))
            .toList();
        _residents = (results[1] as List)
            .map((j) => Resident.fromJson(j as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) _notify('Could not load rooms and residents', isError: true);
    }
  }

  void _notify(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _red : null,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        margin: const EdgeInsets.only(bottom: 24, left: 60, right: 60),
      ),
    );
  }

  List<Resident> _occupantsOf(int roomId) =>
      _residents.where((r) => r.roomId == roomId).toList();

  List<Resident> get _unassigned =>
      _residents.where((r) => r.roomId == null).toList();

  Future<void> _confirmRemove(Resident resident) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unassign from room?'),
        content: Text(
          'Remove ${resident.displayName} from Room ${resident.roomNumber} and move them to unassigned?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Unassign', style: TextStyle(color: _red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busyResidentId = resident.residentId);
    try {
      // PATCH .../unassign clears room_id without touching the resident
      // record — plain DELETE /residents/:id is now a REAL delete (the two
      // routes no longer collide, so they're intentionally different actions).
      await ApiService.patch('/residents/${resident.residentId}/unassign', {});
      if (mounted) _notify('Moved to unassigned');
      await _loadAll();
    } on ApiException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    } catch (e) {
      if (mounted) _notify('Could not remove from room', isError: true);
    } finally {
      if (mounted) {
        setState(() => _busyResidentId = null);
      }
    }
  }

  Future<void> _openNewRoomSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewRoomSheet(),
    );
    if (created == true) {
      _notify('Room created');
      _loadAll();
    }
  }

  Future<void> _openAssignSheet({int? userId, int? roomId}) async {
    final assigned = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AssignSheet(
        rooms: _rooms,
        residents: _residents,
        initialUserId: userId,
        initialRoomId: roomId,
      ),
    );
    if (assigned == true) {
      _notify('Resident assigned to room');
      _loadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStaff = context.watch<AuthProvider>().user?.roleId == 1;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rooms'),
        actions: isStaff
            ? [
                IconButton(
                  onPressed: () => _openAssignSheet(),
                  icon: const Icon(Icons.meeting_room_outlined),
                  tooltip: 'Assign resident',
                ),
                IconButton(
                  onPressed: _openNewRoomSheet,
                  icon: const Icon(Icons.add),
                  tooltip: 'New room',
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (isStaff && _unassigned.isNotEmpty) ...[
                    _buildUnassignedBanner(colors),
                    const SizedBox(height: 16),
                  ],
                  if (_rooms.isEmpty)
                    _buildEmptyState(colors, isStaff)
                  else
                    ..._rooms.map(
                      (room) => _buildRoomCard(context, colors, isStaff, room),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildUnassignedBanner(ColorScheme colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_outline, size: 16, color: _amber),
              const SizedBox(width: 6),
              Text(
                'Unassigned residents (${_unassigned.length})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _unassigned.map((r) {
              return GestureDetector(
                onTap: () => _openAssignSheet(userId: r.userId),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _amber.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    r.displayName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _amber,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colors, bool isStaff) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.home_outlined, size: 32, color: colors.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            'No rooms yet',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
          if (isStaff) ...[
            const SizedBox(height: 4),
            Text(
              'Use "New room" to add the first one.',
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  /// The "trunk" — a room card, with its occupants branching off it below.
  Widget _buildRoomCard(
    BuildContext context,
    ColorScheme colors,
    bool isStaff,
    Room room,
  ) {
    final occupants = _occupantsOf(room.roomId);
    final full = room.currentOccupancy >= room.maxCapacity;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- trunk ---
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Room ${room.roomNumber}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: (full ? _red : _green).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${room.currentOccupancy}/${room.maxCapacity} occupied',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: full ? _red : _green,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isStaff && !full)
                IconButton(
                  onPressed: () => _openAssignSheet(roomId: room.roomId),
                  icon: Icon(
                    Icons.person_add_alt_1_outlined,
                    size: 19,
                    color: colors.onSurfaceVariant,
                  ),
                  tooltip: 'Assign someone here',
                ),
            ],
          ),

          // --- branches ---
          if (occupants.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Empty',
                style: TextStyle(
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                  color: colors.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            const SizedBox(height: 12),
            ...occupants.map(
              (o) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    // the little branch connector
                    SizedBox(
                      width: 18,
                      child: CustomPaint(
                        painter: _BranchPainter(color: colors.outlineVariant),
                      ),
                    ),
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: const Color(0xFF3355FF),
                      child: Text(
                        o.displayName.isNotEmpty
                            ? o.displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        o.displayName,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: colors.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isStaff)
                      _busyResidentId == o.residentId
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.onSurfaceVariant,
                              ),
                            )
                          : IconButton(
                              onPressed: () => _confirmRemove(o),
                              icon: Icon(
                                Icons.person_remove_outlined,
                                size: 17,
                                color: colors.onSurfaceVariant,
                              ),
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Remove from room',
                            ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Draws a small "└" branch connector to the left of each occupant row.
class _BranchPainter extends CustomPainter {
  final Color color;
  _BranchPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width / 2, -8)
      ..lineTo(size.width / 2, size.height / 2)
      ..lineTo(size.width, size.height / 2);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BranchPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// --- New room sheet ---
class _NewRoomSheet extends StatefulWidget {
  const _NewRoomSheet();

  @override
  State<_NewRoomSheet> createState() => _NewRoomSheetState();
}

class _NewRoomSheetState extends State<_NewRoomSheet> {
  final _roomNumberController = TextEditingController();
  final _capacityController = TextEditingController(text: '2');
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _roomNumberController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_roomNumberController.text.trim().isEmpty) {
      setState(() => _error = 'Give the room a number/name');
      return;
    }
    final cap = int.tryParse(_capacityController.text.trim());
    if (cap == null || cap <= 0) {
      setState(() => _error = 'Capacity must be a positive whole number');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ApiService.post('/rooms', {
        'room_number': _roomNumberController.text.trim(),
        'max_capacity': cap,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not create room');
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
              'New room',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Room number',
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _roomNumberController,
              decoration: _fieldDecoration(colors, hint: 'e.g. 12A'),
            ),
            const SizedBox(height: 14),
            Text(
              'Max capacity',
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _capacityController,
              keyboardType: TextInputType.number,
              decoration: _fieldDecoration(colors),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: _red, fontSize: 13)),
            ],
            const SizedBox(height: 18),
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
                        'Create room',
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
}

/// --- Assign resident sheet ---
class _AssignSheet extends StatefulWidget {
  final List<Room> rooms;
  final List<Resident> residents;
  final int? initialUserId;
  final int? initialRoomId;

  const _AssignSheet({
    required this.rooms,
    required this.residents,
    this.initialUserId,
    this.initialRoomId,
  });

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  int? _selectedUserId;
  int? _selectedRoomId;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedUserId = widget.initialUserId;
    _selectedRoomId = widget.initialRoomId;
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_selectedUserId == null) {
      setState(() => _error = 'Pick a resident');
      return;
    }
    if (_selectedRoomId == null) {
      setState(() => _error = 'Pick a room');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ApiService.post('/residents', {
        'user_id': _selectedUserId,
        'room_id': _selectedRoomId,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not assign resident to room');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selectedResident = widget.residents
        .where((r) => r.userId == _selectedUserId)
        .firstOrNull;

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
            Row(
              children: [
                Icon(
                  Icons.meeting_room_outlined,
                  size: 18,
                  color: colors.onSurface,
                ),
                const SizedBox(width: 8),
                Text(
                  'Assign to room',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Resident',
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _selectedUserId,
              decoration: _fieldDecoration(colors),
              hint: Text(
                widget.residents.isEmpty
                    ? 'No residents found'
                    : 'Select a resident',
              ),
              items: widget.residents
                  .map(
                    (r) => DropdownMenuItem(
                      value: r.userId,
                      child: Text(
                        r.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selectedUserId = v),
            ),
            if (selectedResident?.roomNumber != null) ...[
              const SizedBox(height: 4),
              Text(
                'Currently in Room ${selectedResident!.roomNumber} — this will move them.',
                style: const TextStyle(fontSize: 11, color: _amber),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              'Room',
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _selectedRoomId,
              decoration: _fieldDecoration(colors),
              hint: Text(
                widget.rooms.isEmpty ? 'No rooms found' : 'Select a room',
              ),
              items: widget.rooms.map((room) {
                final full = room.currentOccupancy >= room.maxCapacity;
                return DropdownMenuItem(
                  value: room.roomId,
                  enabled: !full,
                  child: Text(
                    'Room ${room.roomNumber} — ${room.currentOccupancy}/${room.maxCapacity}${full ? ' (full)' : ''}',
                    style: TextStyle(
                      color: full ? colors.onSurfaceVariant : colors.onSurface,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (v) => setState(() => _selectedRoomId = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: _red, fontSize: 13)),
            ],
            const SizedBox(height: 18),
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
                        'Assign',
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
}

InputDecoration _fieldDecoration(ColorScheme colors, {String? hint}) {
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
      borderSide: const BorderSide(color: Color(0xFF3355FF)),
    ),
  );
}
