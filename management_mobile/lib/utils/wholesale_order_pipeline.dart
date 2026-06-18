import '../models/wholesale_order.dart';

enum WholesalePipelineSection {
  orderConfirmEmail,
  shipments,
  deliveryCompleteEmail,
  invoiceEmail,
  payment,
}

class WholesalePipelineInputs {
  const WholesalePipelineInputs({
    required this.order,
    required this.allocationConfirmed,
    required this.orderConfirmEmailDone,
    required this.allShipmentsCompleted,
    required this.shipmentsDeliveredEmailDone,
    required this.invoiceEmailDone,
    required this.paymentComplete,
    required this.hasInvoiceDocument,
  });

  final WholesaleOrder order;
  final bool allocationConfirmed;
  final bool orderConfirmEmailDone;
  final bool allShipmentsCompleted;
  final bool shipmentsDeliveredEmailDone;
  final bool invoiceEmailDone;
  final bool paymentComplete;
  final bool hasInvoiceDocument;
}

class WholesalePipelineUiState {
  const WholesalePipelineUiState({
    required this.sections,
    required this.currentIndex,
    required this.previewVisible,
    required this.inputs,
  });

  final List<WholesalePipelineSection> sections;
  /// -1 = still in assign/allocation; [sections.length] = pipeline complete.
  final int currentIndex;
  final bool previewVisible;
  final WholesalePipelineInputs inputs;

  bool isDone(WholesalePipelineSection section) {
    switch (section) {
      case WholesalePipelineSection.orderConfirmEmail:
        return inputs.orderConfirmEmailDone;
      case WholesalePipelineSection.shipments:
        return inputs.allShipmentsCompleted;
      case WholesalePipelineSection.deliveryCompleteEmail:
        return inputs.shipmentsDeliveredEmailDone;
      case WholesalePipelineSection.invoiceEmail:
        return inputs.invoiceEmailDone;
      case WholesalePipelineSection.payment:
        return inputs.paymentComplete;
    }
  }

  bool shouldShow(WholesalePipelineSection section) {
    if (!previewVisible) return false;
    final idx = sections.indexOf(section);
    if (idx < 0) return false;
    if (isDone(section)) return true;
    if (currentIndex < 0) return true;
    return idx >= currentIndex;
  }

  bool isDimmed(WholesalePipelineSection section) {
    if (isDone(section)) return false;
    final idx = sections.indexOf(section);
    if (idx < 0) return false;
    if (currentIndex < 0) return true;
    return idx > currentIndex;
  }

  bool isActive(WholesalePipelineSection section) {
    if (currentIndex < 0) return false;
    return sections.indexOf(section) == currentIndex && !isDone(section);
  }
}

WholesalePipelineUiState buildWholesalePipelineUiState(WholesalePipelineInputs inputs) {
  final order = inputs.order;
  final previewVisible = order.status != 'rejected' && order.status != 'deleted';

  final sections = <WholesalePipelineSection>[
    WholesalePipelineSection.orderConfirmEmail,
    WholesalePipelineSection.shipments,
    WholesalePipelineSection.deliveryCompleteEmail,
  ];
  if (inputs.hasInvoiceDocument) {
    sections.add(WholesalePipelineSection.invoiceEmail);
  }
  sections.add(WholesalePipelineSection.payment);

  var currentIndex = sections.length;
  if (previewVisible) {
    if (!inputs.allocationConfirmed) {
      currentIndex = -1;
    } else if (!inputs.orderConfirmEmailDone) {
      currentIndex = 0;
    } else if (!inputs.allShipmentsCompleted) {
      currentIndex = sections.indexOf(WholesalePipelineSection.shipments);
    } else if (!inputs.shipmentsDeliveredEmailDone) {
      currentIndex = sections.indexOf(WholesalePipelineSection.deliveryCompleteEmail);
    } else if (inputs.hasInvoiceDocument) {
      if (!inputs.invoiceEmailDone) {
        currentIndex = sections.indexOf(WholesalePipelineSection.invoiceEmail);
      } else if (!inputs.paymentComplete) {
        currentIndex = sections.indexOf(WholesalePipelineSection.payment);
      }
    } else if (!inputs.paymentComplete) {
      currentIndex = sections.indexOf(WholesalePipelineSection.payment);
    }
  }

  return WholesalePipelineUiState(
    sections: sections,
    currentIndex: currentIndex,
    previewVisible: previewVisible,
    inputs: inputs,
  );
}

bool wholesaleAssignSectionActive({
  required WholesaleOrder order,
  required bool showAssignPanel,
}) {
  if (order.status == 'rejected' || order.status == 'deleted') return false;
  return showAssignPanel;
}
