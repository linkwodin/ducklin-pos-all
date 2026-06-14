bool shipmentNeedsPacking(String status) {
  return status == 'assigned' || status == 'packing';
}

bool isShipmentCompleted(String status) => status == 'completed';
