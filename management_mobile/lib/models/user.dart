import 'store.dart';

class AppUser {
  final int id;
  final String username;
  final String role;
  final String firstName;
  final String lastName;
  final String? email;
  final String? iconUrl;
  final String? iconBgColor;
  final String? iconTextColor;
  final bool isActive;
  final List<Store> stores;

  const AppUser({
    required this.id,
    required this.username,
    required this.role,
    required this.firstName,
    required this.lastName,
    this.email,
    this.iconUrl,
    this.iconBgColor,
    this.iconTextColor,
    this.isActive = true,
    this.stores = const [],
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final idRaw = json['id'];
    final id = idRaw is int ? idRaw : int.parse('$idRaw');
    final storesRaw = json['stores'] as List<dynamic>? ?? [];
    return AppUser(
      id: id,
      username: '${json['username'] ?? ''}',
      role: '${json['role'] ?? ''}',
      firstName: '${json['first_name'] ?? ''}',
      lastName: '${json['last_name'] ?? ''}',
      email: json['email']?.toString(),
      iconUrl: json['icon_url']?.toString(),
      iconBgColor: json['icon_bg_color']?.toString(),
      iconTextColor: json['icon_text_color']?.toString(),
      isActive: json['is_active'] != false,
      stores: storesRaw.map((e) => Store.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'role': role,
        'first_name': firstName,
        'last_name': lastName,
        if (email != null) 'email': email,
        if (iconUrl != null) 'icon_url': iconUrl,
        if (iconBgColor != null) 'icon_bg_color': iconBgColor,
        if (iconTextColor != null) 'icon_text_color': iconTextColor,
        'is_active': isActive,
      };

  String get displayName {
    final name = '$firstName $lastName'.trim();
    return name.isNotEmpty ? name : username;
  }

  bool get canUseManagementPortal =>
      role == 'management' || role == 'supervisor';
}

class AdminUser extends AppUser {
  const AdminUser({
    required super.id,
    required super.username,
    required super.role,
    required super.firstName,
    required super.lastName,
    super.email,
    super.iconUrl,
    super.iconBgColor,
    super.iconTextColor,
    super.isActive,
    super.stores,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: json['id'] as int,
        username: '${json['username'] ?? ''}',
        role: '${json['role'] ?? ''}',
        firstName: '${json['first_name'] ?? ''}',
        lastName: '${json['last_name'] ?? ''}',
        email: json['email']?.toString(),
        iconUrl: json['icon_url']?.toString(),
        iconBgColor: json['icon_bg_color']?.toString(),
        iconTextColor: json['icon_text_color']?.toString(),
        isActive: json['is_active'] != false,
        stores: (json['stores'] as List<dynamic>? ?? [])
            .map((e) => Store.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
