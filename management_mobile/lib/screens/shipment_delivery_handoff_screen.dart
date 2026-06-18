import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n_labels.dart';
import '../models/shipment.dart';
import '../services/api_service.dart';
import '../utils/formatters.dart';
import '../utils/shipment_packing.dart';
import '../widgets/async_body.dart';
import '../widgets/media_picker.dart';
import '../widgets/status_chip.dart';

class ShipmentDeliveryHandoffScreen extends StatefulWidget {
  const ShipmentDeliveryHandoffScreen({super.key, required this.shipmentId});

  final int shipmentId;

  @override
  State<ShipmentDeliveryHandoffScreen> createState() => _ShipmentDeliveryHandoffScreenState();
}

class _ShipmentDeliveryHandoffScreenState extends State<ShipmentDeliveryHandoffScreen> {
  var _loading = true;
  var _error = '';
  var _actioning = false;
  Shipment? _shipment;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final shipment = await ApiService.instance.getShipment(widget.shipmentId);
      if (!mounted) return;
      setState(() {
        _shipment = shipment;
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

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _actioning = true);
    try {
      await action();
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
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

  Future<void> _uploadSignedDeliveryNote(Shipment shipment) async {
    await MediaPicker.showSourceSheet(context, onPicked: (paths) async {
      if (paths.isEmpty || _actioning) return;
      await _run(
        () => ApiService.instance.uploadSignedDeliveryNote(shipment.id, paths.first),
        AppLocalizations.of(context)!.workflowHandoffUploaded,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final shipment = _shipment;
    final canUpload = shipment != null && shipmentCanUploadDeliveryProof(shipment);
    final hasProof = shipment != null && shipmentHasDeliveryProof(shipment);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(shipment?.orderNumber ?? l10n.workflowHandoff),
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
                  StatusChip(
                    label: l10n.shipmentStatusLabel(shipment.status),
                    color: shipmentStatusChipColor(shipment.status),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.deliveryHandoffHint,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
                  ),
                  if ((shipment.courier ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.local_shipping_outlined),
                      title: Text(shipment.courier!.trim()),
                      subtitle: (shipment.trackingNumber ?? '').trim().isNotEmpty
                          ? Text('${l10n.tracking}: ${shipment.trackingNumber!.trim()}')
                          : null,
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (canUpload)
                    FilledButton.icon(
                      onPressed: _actioning ? null : () => _uploadSignedDeliveryNote(shipment),
                      icon: const Icon(Icons.upload_file),
                      label: Text(l10n.workflowHandoffUploadShipped),
                    ),
                  if (shipment.status == 'packed') ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _actioning
                          ? null
                          : () => _run(
                                () => ApiService.instance.updateShipmentStatus(shipment.id, 'shipped'),
                                l10n.markedShippedSnack,
                              ),
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(l10n.markShipped),
                    ),
                  ],
                  if (hasProof) ...[
                    const SizedBox(height: 16),
                    Text(
                      l10n.workflowHandoffUploaded,
                      style: TextStyle(color: Colors.green.shade800),
                    ),
                  ],
                  if (shipment.status == 'shipped' && !hasProof) ...[
                    const SizedBox(height: 16),
                    Text(
                      l10n.shipmentMarkedAwaitProof,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
