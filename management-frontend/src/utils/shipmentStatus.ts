import type { Shipment } from '../types';
import type { TFunction } from 'i18next';

export type ShipmentStatus = 'assigned' | 'packed' | 'shipped' | 'completed' | 'packing';

export function isShipmentCompleted(status: string): boolean {
  return status === 'completed';
}

export function shipmentNeedsPacking(status: string): boolean {
  return status === 'assigned' || status === 'packing';
}

export function shipmentHasDeliveryNoteStarted(shipment: Pick<Shipment, 'status' | 'delivery_note_pdf_url'>): boolean {
  return (
    !!shipment.delivery_note_pdf_url?.trim() ||
    shipment.status === 'packed' ||
    shipment.status === 'shipped' ||
    shipment.status === 'completed'
  );
}

export function shipmentHasDeliveryProof(
  shipment: Pick<Shipment, 'signed_delivery_note_pdf_url'>,
): boolean {
  return !!shipment.signed_delivery_note_pdf_url?.trim();
}

export function canEditShipmentDetails(
  shipment: Pick<Shipment, 'signed_delivery_note_pdf_url'>,
): boolean {
  return !shipmentHasDeliveryProof(shipment);
}

export function canUploadDeliveryProof(
  shipment: Pick<Shipment, 'status' | 'delivery_note_pdf_url' | 'signed_delivery_note_pdf_url'>,
): boolean {
  if (isShipmentCompleted(shipment.status)) return false;
  if (!shipment.delivery_note_pdf_url?.trim()) return false;
  if (shipmentHasDeliveryProof(shipment)) return false;
  return shipment.status === 'packed' || shipment.status === 'shipped';
}

/** Packed with a delivery note but courier has not collected yet (no signed proof). */
export function shipmentAwaitingCourierPickup(
  shipment: Pick<Shipment, 'status' | 'delivery_note_pdf_url' | 'signed_delivery_note_pdf_url'>,
): boolean {
  if (shipment.status !== 'packed') return false;
  if (!shipment.delivery_note_pdf_url?.trim()) return false;
  return !shipmentHasDeliveryProof(shipment);
}

/** After delivery proof exists, allow uploading a new file to replace it (shipment stays completed). */
export function canReplaceDeliveryProof(
  shipment: Pick<Shipment, 'status' | 'delivery_note_pdf_url' | 'signed_delivery_note_pdf_url'>,
): boolean {
  if (!shipment.delivery_note_pdf_url?.trim()) return false;
  if (!shipmentHasDeliveryProof(shipment)) return false;
  return isShipmentCompleted(shipment.status);
}

export function shipmentStatusLabel(status: string, t: TFunction): string {
  switch (status) {
    case 'assigned':
    case 'packing':
      return t('wholesaleOrderDetail:shipmentStatusAssigned');
    case 'packed':
      return t('wholesaleOrderDetail:shipmentStatusPacked');
    case 'shipped':
      return t('wholesaleOrderDetail:shipmentStatusShipped');
    case 'completed':
      return t('wholesaleOrderDetail:shipmentStatusCompleted');
    default:
      return status.replace(/_/g, ' ');
  }
}

export function shipmentStatusChipColor(
  status: string,
): 'default' | 'info' | 'warning' | 'success' {
  switch (status) {
    case 'completed':
      return 'success';
    case 'shipped':
      return 'warning';
    case 'packed':
      return 'info';
    default:
      return 'default';
  }
}
