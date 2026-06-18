class Store {
  final int id;
  final String name;
  final String? address;
  final bool isWarehouseOnly;
  final bool isActive;

  const Store({
    required this.id,
    required this.name,
    this.address,
    this.isWarehouseOnly = false,
    this.isActive = true,
  });

  factory Store.fromJson(Map<String, dynamic> json) => Store(
        id: json['id'] as int,
        name: '${json['name'] ?? ''}',
        address: json['address']?.toString(),
        isWarehouseOnly: json['is_warehouse_only'] == true,
        isActive: json['is_active'] != false,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (address != null) 'address': address,
        'is_warehouse_only': isWarehouseOnly,
        'is_active': isActive,
      };
}
