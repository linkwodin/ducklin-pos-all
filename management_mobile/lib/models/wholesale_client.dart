import 'sector.dart';

class WholesaleClientStore {
  final int id;
  final int wholesaleClientId;
  final String name;
  final String? addressLine1;
  final String? city;
  final String? postcode;
  final bool isActive;

  const WholesaleClientStore({
    required this.id,
    required this.wholesaleClientId,
    required this.name,
    this.addressLine1,
    this.city,
    this.postcode,
    this.isActive = true,
  });

  factory WholesaleClientStore.fromJson(Map<String, dynamic> json) =>
      WholesaleClientStore(
        id: json['id'] as int,
        wholesaleClientId: json['wholesale_client_id'] as int,
        name: '${json['name'] ?? ''}',
        addressLine1: json['address_line1']?.toString(),
        city: json['city']?.toString(),
        postcode: json['postcode']?.toString(),
        isActive: json['is_active'] != false,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (addressLine1 != null) 'address_line1': addressLine1,
        if (city != null) 'city': city,
        if (postcode != null) 'postcode': postcode,
        'is_active': isActive,
      };

  String summary() {
    final parts = [addressLine1, city, postcode].where((p) => p != null && p.isNotEmpty).cast<String>();
    return parts.isEmpty ? name : '${parts.join(', ')}';
  }
}

class WholesaleClient {
  final int id;
  final String name;
  final String? contactName;
  final String? email;
  final String? phone;
  final String? terms;
  final int? sectorId;
  final Sector? sector;
  final List<WholesaleClientStore> stores;
  final bool isActive;

  const WholesaleClient({
    required this.id,
    required this.name,
    this.contactName,
    this.email,
    this.phone,
    this.terms,
    this.sectorId,
    this.sector,
    this.stores = const [],
    this.isActive = true,
  });

  factory WholesaleClient.fromJson(Map<String, dynamic> json) {
    final storesRaw = json['stores'] as List<dynamic>? ?? [];
    return WholesaleClient(
      id: json['id'] as int,
      name: '${json['name'] ?? ''}',
      contactName: json['contact_name']?.toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      terms: json['terms']?.toString(),
      sectorId: json['sector_id'] as int?,
      sector: json['sector'] != null
          ? Sector.fromJson(json['sector'] as Map<String, dynamic>)
          : null,
      stores: storesRaw
          .map((e) => WholesaleClientStore.fromJson(e as Map<String, dynamic>))
          .toList(),
      isActive: json['is_active'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (contactName != null) 'contact_name': contactName,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (terms != null) 'terms': terms,
        if (sectorId != null) 'sector_id': sectorId,
        'is_active': isActive,
      };
}
