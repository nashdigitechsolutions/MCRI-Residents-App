class Room {
  final int roomId;
  final String roomNumber;
  final int currentOccupancy;
  final int maxCapacity;

  Room({
    required this.roomId,
    required this.roomNumber,
    required this.currentOccupancy,
    required this.maxCapacity,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      roomId: json['room_id'] is String
          ? int.parse(json['room_id'])
          : json['room_id'] as int,
      roomNumber: json['room_number'].toString(),
      currentOccupancy: json['current_occupancy'] as int? ?? 0,
      maxCapacity: json['max_capacity'] as int? ?? 0,
    );
  }
}
