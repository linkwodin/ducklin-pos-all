class Sector {
  final int id;
  final String name;
  final String? description;
  final bool isActive;

  const Sector({
    required this.id,
    required this.name,
    this.description,
    this.isActive = true,
  });

  factory Sector.fromJson(Map<String, dynamic> json) => Sector(
        id: json['id'] as int,
        name: '${json['name'] ?? ''}',
        description: json['description']?.toString(),
        isActive: json['is_active'] != false,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        'is_active': isActive,
      };
}
