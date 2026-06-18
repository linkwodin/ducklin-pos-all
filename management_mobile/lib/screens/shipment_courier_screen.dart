import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/shipment.dart';
import '../services/api_service.dart';
import '../utils/shipment_packing.dart';
import '../utils/shipment_scan.dart';
import '../widgets/async_body.dart';
import '../widgets/date_picker_field.dart';

class ShipmentCourierScreen extends StatefulWidget {
  const ShipmentCourierScreen({super.key, required this.shipmentId});

  final int shipmentId;

  @override
  State<ShipmentCourierScreen> createState() => _ShipmentCourierScreenState();
}

class _ShipmentCourierScreenState extends State<ShipmentCourierScreen> {
  var _loading = true;
  var _error = '';
  var _actioning = false;
  Shipment? _shipment;
  List<String> _courierOptions = [];
  final _courier = TextEditingController();
  final _courierFocus = FocusNode();
  final _tracking = TextEditingController();
  DateTime? _deliveryDate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _courier.dispose();
    _courierFocus.dispose();
    _tracking.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final shipment = await ApiService.instance.getShipment(widget.shipmentId);
      final settings = await ApiService.instance.getCompanySettings();
      if (!mounted) return;
      _courier.text = shipment.courier ?? '';
      _tracking.text = shipment.trackingNumber ?? '';
      _deliveryDate = parseApiDate(shipment.deliveryDate) ?? DateTime.now();
      setState(() {
        _shipment = shipment;
        _courierOptions = courierOptionsFromSettings(settings.shipmentCouriers);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiService.instance.errorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _saveDetails(Shipment shipment) async {
    setState(() => _actioning = true);
    try {
      await ApiService.instance.updateShipment(
        shipment.id,
        courier: _courier.text.trim(),
        trackingNumber: _tracking.text.trim(),
        deliveryDate: _deliveryDate == null ? '' : formatApiDate(_deliveryDate!),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.instance.errorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _actioning = false);
    }
  }

  Iterable<String> _courierSuggestions(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _courierOptions;
    return _courierOptions.where((option) => option.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final shipment = _shipment;
    final canEdit = shipment != null && shipmentCanEditCourierDetails(shipment);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(shipment?.orderNumber ?? l10n.courierDetails),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: shipment == null
            ? const SizedBox.shrink()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    l10n.courierDetailsHint,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 20),
                  RawAutocomplete<String>(
                    textEditingController: _courier,
                    focusNode: _courierFocus,
                    optionsBuilder: (value) => _courierSuggestions(value.text),
                    onSelected: canEdit && !_actioning
                        ? (option) => setState(() => _courier.text = option)
                        : null,
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: canEdit && !_actioning,
                        decoration: InputDecoration(
                          labelText: l10n.courier,
                          hintText: l10n.courierHint,
                        ),
                        onSubmitted: (_) => onFieldSubmitted(),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  dense: true,
                                  title: Text(option),
                                  onTap: () => onSelected(option),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  TextField(
                    controller: _tracking,
                    enabled: canEdit && !_actioning,
                    decoration: InputDecoration(labelText: l10n.trackingNumber),
                  ),
                  DatePickerFormField(
                    value: _deliveryDate,
                    enabled: canEdit && !_actioning,
                    onChanged: (date) => setState(() => _deliveryDate = date),
                  ),
                  const SizedBox(height: 12),
                  if (canEdit)
                    FilledButton(
                      onPressed: _actioning ? null : () => _saveDetails(shipment),
                      child: Text(l10n.saveDetails),
                    ),
                  if (!canEdit && shipmentHasDeliveryProof(shipment)) ...[
                    const SizedBox(height: 16),
                    Text(
                      l10n.deliveryProofLocked,
                      style: TextStyle(color: Colors.green.shade800),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
