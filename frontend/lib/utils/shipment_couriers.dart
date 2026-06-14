const defaultShipmentCouriers = ['In-house', 'DPD', 'Royal Mail'];

List<String> shipmentCourierOptionsFromSettings(String? raw) {
  final lines = (raw ?? '')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  return lines.isNotEmpty ? lines : List<String>.from(defaultShipmentCouriers);
}
