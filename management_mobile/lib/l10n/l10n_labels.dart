import '../models/wholesale_order.dart';
import '../utils/wholesale_order_workflow.dart';
import 'app_localizations.dart';

extension AppLocalizationsLabels on AppLocalizations {
  String shipmentStatusLabel(String status) {
    switch (status) {
      case 'assigned':
        return shipmentStatusAssigned;
      case 'packing':
        return shipmentStatusPacking;
      case 'packed':
        return shipmentStatusPacked;
      case 'shipped':
        return shipmentStatusShipped;
      case 'completed':
        return shipmentStatusCompleted;
      default:
        return status.replaceAll('_', ' ');
    }
  }

  String wholesaleOrderStatusFilterLabel(String? value) {
    switch (value) {
      case 'pending_approval':
        return filterPendingApproval;
      case 'assign_shipment':
        return filterAssignShipment;
      case 'awaiting_payment':
        return filterAwaitingPayment;
      case 'completed':
        return filterCompleted;
      case 'rejected':
        return filterRejected;
      case 'deleted':
        return filterDeleted;
      default:
        return all;
    }
  }

  String wholesaleStatusLabel(String status) {
    switch (status) {
      case 'pending_approval':
        return wholesaleStatusPendingApproval;
      case 'assign_shipment':
        return wholesaleStatusAssignShipment;
      case 'approved':
        return wholesaleStatusApproved;
      case 'rejected':
        return wholesaleStatusRejected;
      case 'deleted':
        return wholesaleStatusDeleted;
      default:
        return status.replaceAll('_', ' ');
    }
  }

  String wholesaleOrderWorkflowStatusLabel(WholesaleOrder order, WholesaleWorkflowContext ctx) {
    if (order.status == 'rejected') return wholesaleStatusRejected;
    if (order.status == 'deleted') return wholesaleStatusDeleted;

    final steps = computeWholesaleOrderProcessSteps(order, ctx);
    if (steps.every((s) => s.done)) return wholesaleStatusCompleted;

    switch (currentWholesaleProcessStepKey(steps)) {
      case WholesaleProcessStepKey.stepOrderConfirmation:
        return wholesaleStatusPendingOrderConfirmation;
      case WholesaleProcessStepKey.stepStartShipment:
        return wholesaleStatusPendingPacking;
      case WholesaleProcessStepKey.stepFinishShipment:
        return wholesaleStatusInTransit;
      case WholesaleProcessStepKey.stepSendInvoiceEmail:
      case WholesaleProcessStepKey.stepPaymentConfirmation:
        return wholesaleStatusPendingPayment;
      case WholesaleProcessStepKey.stepComplete:
        return wholesaleStatusCompleted;
      default:
        return wholesaleStatusLabel(order.status);
    }
  }

  String posOrderStatusFilterLabel(String? value) {
    switch (value) {
      case 'pending':
        return posFilterPending;
      case 'paid':
        return posFilterPaid;
      case 'picked_up':
        return posFilterPickedUp;
      case 'completed':
        return filterCompleted;
      case 'cancelled':
        return posFilterCancelled;
      default:
        return all;
    }
  }

  String restockStatusLabel(String status) {
    switch (status) {
      case 'initiated':
        return restockStatusInitiated;
      case 'in_transit':
        return restockStatusInTransit;
      case 'received':
        return restockStatusReceived;
      default:
        return status.replaceAll('_', ' ');
    }
  }

  String wholesaleProcessStepLabel(WholesaleProcessStepKey key) {
    switch (key) {
      case WholesaleProcessStepKey.stepCreate:
        return stepCreated;
      case WholesaleProcessStepKey.stepOrderConfirmation:
        return stepOrderConfirmation;
      case WholesaleProcessStepKey.stepStartShipment:
        return stepStartShipment;
      case WholesaleProcessStepKey.stepFinishShipment:
        return stepFinishShipment;
      case WholesaleProcessStepKey.stepSendInvoiceEmail:
        return stepInvoiceEmail;
      case WholesaleProcessStepKey.stepPaymentConfirmation:
        return stepPaymentConfirmation;
      case WholesaleProcessStepKey.stepComplete:
        return stepComplete;
    }
  }
}

/// Status filter values for wholesale orders (labels via [AppLocalizationsLabels]).
const wholesaleOrderStatusFilterValues = <String?>[
  null,
  'pending_approval',
  'assign_shipment',
  'awaiting_payment',
  'completed',
  'rejected',
  'deleted',
];
