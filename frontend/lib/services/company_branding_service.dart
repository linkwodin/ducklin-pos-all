import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'image_cache_service.dart';

/// Cached company name and logo for POS UI and receipts (offline-friendly).
class CompanyBrandingService {
  CompanyBrandingService._();
  static final CompanyBrandingService instance = CompanyBrandingService._();

  static const _keyName = 'company_branding_name';
  static const _keyLogoUrl = 'company_branding_logo_url';

  Future<Map<String, String>> getCached() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'company_name': prefs.getString(_keyName) ?? '',
      'logo_url': prefs.getString(_keyLogoUrl) ?? '',
    };
  }

  Future<void> refreshFromApi() async {
    try {
      final online = await ApiService.instance.healthCheck();
      if (!online) return;
      final settings = await ApiService.instance.getPublicCompanyBranding();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyName, settings['company_name']?.toString() ?? '');
      final rawLogo = settings['pos_logo_url']?.toString().trim().isNotEmpty == true
          ? settings['pos_logo_url']!.toString()
          : (settings['logo_url']?.toString() ?? '');
      await prefs.setString(
        _keyLogoUrl,
        rawLogo.isNotEmpty ? ApiService.instance.resolveAssetUrl(rawLogo) : '',
      );
    } catch (e) {
      // Keep cached branding when offline or API fails.
    }
  }

  /// Company name plus optional local logo path for receipt printing.
  Future<Map<String, String?>> resolveForReceipt() async {
    final branding = await getCached();
    final companyName = branding['company_name']?.trim() ?? '';
    final logoUrl = branding['logo_url']?.trim() ?? '';
    String? logoPath;
    if (logoUrl.isNotEmpty) {
      logoPath = await ImageCacheService.getOrDownload(logoUrl);
    }
    return {
      'company_name': companyName,
      'logo_path': logoPath,
    };
  }
}
