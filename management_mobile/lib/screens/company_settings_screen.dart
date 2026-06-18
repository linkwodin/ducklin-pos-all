import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';

class CompanySettingsScreen extends StatefulWidget {
  const CompanySettingsScreen({super.key});

  @override
  State<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends State<CompanySettingsScreen> {
  var _loading = true;
  var _saving = false;
  final _companyName = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _postcode = TextEditingController();
  final _telephone = TextEditingController();
  final _email = TextEditingController();
  final _paymentInfo = TextEditingController();
  final _couriers = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _companyName.dispose();
    _address.dispose();
    _city.dispose();
    _postcode.dispose();
    _telephone.dispose();
    _email.dispose();
    _paymentInfo.dispose();
    _couriers.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await ApiService.instance.getCompanySettings();
      _companyName.text = settings.companyName;
      _address.text = settings.addressLine1;
      _city.text = settings.city;
      _postcode.text = settings.postcode;
      _telephone.text = settings.telephone;
      _email.text = settings.email;
      _paymentInfo.text = settings.paymentInfo;
      _couriers.text = settings.shipmentCouriers ?? '';
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.instance.errorMessage(e))),
        );
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiService.instance.updateCompanySettings({
        'company_name': _companyName.text.trim(),
        'address_line1': _address.text.trim(),
        'city': _city.text.trim(),
        'postcode': _postcode.text.trim(),
        'telephone': _telephone.text.trim(),
        'email': _email.text.trim(),
        'payment_info': _paymentInfo.text.trim(),
        'shipment_couriers': _couriers.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.settingsSaved)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.instance.errorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(controller: _companyName, decoration: InputDecoration(labelText: l10n.companyName)),
        TextField(controller: _address, decoration: InputDecoration(labelText: l10n.address)),
        TextField(controller: _city, decoration: InputDecoration(labelText: l10n.city)),
        TextField(controller: _postcode, decoration: InputDecoration(labelText: l10n.postcode)),
        TextField(controller: _telephone, decoration: InputDecoration(labelText: l10n.telephone)),
        TextField(controller: _email, decoration: InputDecoration(labelText: l10n.email)),
        TextField(controller: _paymentInfo, decoration: InputDecoration(labelText: l10n.paymentInfo), maxLines: 3),
        TextField(controller: _couriers, decoration: InputDecoration(labelText: l10n.shipmentCouriersField), maxLines: 2),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.saveSettings),
        ),
      ],
    );
  }
}
