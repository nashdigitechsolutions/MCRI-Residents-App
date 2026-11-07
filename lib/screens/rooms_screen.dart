import 'package:mcri_residents_app/widgets/app_loader.dart';

import '../widgets/app_refresh.dart';

import 'package:mcri_residents_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/resident.dart';
import '../models/room.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/ui.dart';

const _amber = AppColors.warning;
const _red = AppColors.danger;

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

  Future<void> _loadAll({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.get('/rooms'),
        ApiService.get('/residents'),
      ]);
      if (!mounted) return;
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

  String _roomFilter = 'all'; // all | space | full
  String _roomSearch = '';

  List<Room> _visibleRooms(int? myRoomId) {
    final q = _roomSearch.trim().toLowerCase();
    final list = _rooms.where((r) {
      final full = r.currentOccupancy >= r.maxCapacity;
      if (_roomFilter == 'space' && full) return false;
      if (_roomFilter == 'full' && !full) return false;
      if (q.isEmpty) return true;
      return r.roomNumber.toLowerCase().contains(q) ||
          _occupantsOf(r.roomId)
              .any((o) => o.displayName.toLowerCase().contains(q));
    }).toList();
    // My room first, then natural room-number order.
    list.sort((a, b) {
      if (a.roomId == myRoomId) return -1;
      if (b.roomId == myRoomId) return 1;
      final na = int.tryParse(a.roomNumber), nb = int.tryParse(b.roomNumber);
      if (na != null && nb != null) return na.compareTo(nb);
      return a.roomNumber.compareTo(b.roomNumber);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isStaff = auth.user?.roleId == 1;
    final colors = Theme.of(context).colorScheme;
    final me = _residents
        .where((r) => r.userId == auth.user?.userId)
        .firstOrNull;
    final myRoom = _rooms.where((r) => r.roomId == me?.roomId).firstOrNull;
    final beds = _rooms.fold<int>(0, (s, r) => s + r.maxCapacity);
    final taken = _rooms.fold<int>(0, (s, r) => s + r.currentOccupancy);
    final rooms = _visibleRooms(myRoom?.roomId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rooms'),
        actions: isStaff
            ? [
                IconButton(
                  onPressed: () => _openAssignSheet(),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
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
          ? const AppLoadingView(message: 'Loading rooms…')
          : AppRefreshIndicator(
              onRefresh: () => _loadAll(showLoading: false),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  const PageHeading(
                    eyebrow: 'Residence',
                    title: 'Rooms',
                    subtitle: 'Who lives where, and where there\'s space',
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _summaryTile(
                        colors,
                        Icons.door_front_door_outlined,
                        '${_rooms.length}',
                        'Rooms',
                      ),
                      const SizedBox(width: 8),
                      _summaryTile(
                        colors,
                        Icons.bed_outlined,
                        '${(beds - taken).clamp(0, beds)}',
                        'Beds free',
                      ),
                      const SizedBox(width: 8),
                      _summaryTile(
                        colors,
                        Icons.groups_2_outlined,
                        '$taken',
                        'Residents',
                      ),
                    ],
                  ),
                  if (myRoom != null) ...[
                    const SizedBox(height: 14),
                    _myRoomCard(myRoom),
                  ],
                  if (isStaff && _unassigned.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _buildUnassignedBanner(colors),
                  ],
                  const SizedBox(height: 16),
                  if (_rooms.length > 3) ...[
                    TextField(
                      onChanged: (v) => setState(() => _roomSearch = v),
                      decoration: InputDecoration(
                        hintText: 'Search a room or a resident…',
                        prefixIcon: Icon(
                          Icons.search,
                          size: 19,
                          color: colors.onSurfaceVariant,
                        ),
                        filled: true,
                        fillColor: colors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide(color: colors.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide(color: colors.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final (k, l) in [
                          ('all', 'All'),
                          ('space', 'Has space'),
                          ('full', 'Full'),
                        ])
                          ChoiceChip(
                            label: Text(l),
                            selected: _roomFilter == k,
                            onSelected: (_) => setState(() => _roomFilter = k),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_rooms.isEmpty)
                    _buildEmptyState(colors, isStaff)
                  else if (rooms.isEmpty)
                    const EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No rooms match',
                      message: 'Try another search or filter.',
                    )
                  else
                    ...rooms.map(
                      (room) => _buildRoomCard(
                        context,
                        colors,
                        isStaff,
                        room,
                        mine: room.roomId == myRoom?.roomId,
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _summaryTile(
    ColorScheme colors,
    IconData icon,
    String value,
    String label,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _myRoomCard(Room room) {
    final mates = _occupantsOf(room.roomId)
        .where((o) => o.userId != context.read<AuthProvider>().user?.userId)
        .toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.ink, Color(0xFF2A160B), AppColors.primaryDeep],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            alignment: Alignment.center,
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  room.roomNumber,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'YOUR ROOM',
                  style: TextStyle(
                    color: AppColors.primaryBorder,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Room ${room.roomNumber}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  mates.isEmpty
                      ? 'Just you for now'
                      : 'With ${mates.map((m) => m.displayName.split(' ').first).join(', ')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnassignedBanner(ColorScheme colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_search_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_unassigned.length} resident${_unassigned.length == 1 ? '' : 's'} without a room',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a name to give them a room.',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in _unassigned)
                ActionChip(
                  avatar: CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: Text(
                      r.displayName.isNotEmpty
                          ? r.displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  label: Text(r.displayName),
                  onPressed: () => _openAssignSheet(userId: r.userId),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colors, bool isStaff) {
    return EmptyState(
      icon: Icons.door_front_door_outlined,
      title: 'No rooms yet',
      message: isStaff
          ? 'Tap + to add the first room.'
          : 'Rooms will show here once they\'re set up.',
    );
  }

  /// Room card: number tile, a bed per place (filled = taken), occupants.
  Widget _buildRoomCard(
    BuildContext context,
    ColorScheme colors,
    bool isStaff,
    Room room, {
    bool mine = false,
  }) {
    final occupants = _occupantsOf(room.roomId);
    final full = room.currentOccupancy >= room.maxCapacity;
    final free = (room.maxCapacity - room.currentOccupancy).clamp(
      0,
      room.maxCapacity,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: mine ? AppColors.primary : colors.outlineVariant,
          width: mine ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: full
                      ? colors.surfaceContainerHighest
                      : colors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                ),
                alignment: Alignment.center,
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      room.roomNumber,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: full
                            ? colors.onSurfaceVariant
                            : AppColors.primary,
                      ),
                    ),
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
                        Text(
                          'Room ${room.roomNumber}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                        if (mine) ...[
                          const SizedBox(width: 6),
                          const Text(
                            '· YOURS',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    // One bed icon per place: filled = taken, outline = free.
                    Semantics(
                      label:
                          '${room.currentOccupancy} of ${room.maxCapacity} beds taken',
                      child: Wrap(
                        spacing: 3,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (
                            var i = 0;
                            i < room.maxCapacity.clamp(0, 12);
                            i++
                          )
                            Icon(
                              i < room.currentOccupancy
                                  ? Icons.bed_rounded
                                  : Icons.bed_outlined,
                              size: 17,
                              color: i < room.currentOccupancy
                                  ? AppColors.primary
                                  : colors.outlineVariant,
                            ),
                          const SizedBox(width: 4),
                          Text(
                            full ? 'Full' : '$free free',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (isStaff && !full)
                IconButton(
                  onPressed: () => _openAssignSheet(roomId: room.roomId),
                  icon: const Icon(
                    Icons.person_add_alt_1_outlined,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  tooltip: 'Assign someone here',
                ),
            ],
          ),
          if (occupants.isNotEmpty) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: colors.outlineVariant),
            const SizedBox(height: 6),
            for (final o in occupants)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: colors.primaryContainer,
                      child: Text(
                        o.displayName.isNotEmpty
                            ? o.displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        o.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isStaff)
                      _busyResidentId == o.residentId
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: AppLoader(
                                strokeWidth: 2,
                                color: colors.onSurfaceVariant,
                              ),
                            )
                          : IconButton(
                              onPressed: () => _confirmRemove(o),
                              icon: Icon(
                                Icons.person_remove_outlined,
                                size: 18,
                                color: colors.onSurfaceVariant,
                              ),
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Move out of this room',
                            ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                    borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                  ),
                ),
                child: _submitting
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: AppLoader(strokeWidth: 2, color: colors.surface),
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                    borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                  ),
                ),
                child: _submitting
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: AppLoader(strokeWidth: 2, color: colors.surface),
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
      borderSide: const BorderSide(color: AppColors.primary),
    ),
  );
}
