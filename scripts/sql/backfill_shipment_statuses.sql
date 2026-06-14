-- Backfill wholesale shipment statuses for Assigned / Packed / Shipped / Completed flow.
-- Run once against existing databases after deploying the status change.

-- Legacy "packing" -> assigned
UPDATE shipments SET status = 'assigned' WHERE status = 'packing';

-- POS/management completed packing without delivery proof -> packed
UPDATE shipments
SET status = 'packed'
WHERE status = 'completed'
  AND COALESCE(TRIM(delivery_note_pdf_url), '') <> ''
  AND COALESCE(TRIM(signed_delivery_note_pdf_url), '') = ''
  AND COALESCE(TRIM(tracking_number), '') = '';

-- Courier auto-completed without signed proof -> shipped
UPDATE shipments
SET status = 'shipped'
WHERE status = 'completed'
  AND COALESCE(TRIM(tracking_number), '') <> ''
  AND COALESCE(TRIM(signed_delivery_note_pdf_url), '') = '';

-- Rows with signed proof remain completed (no change needed).
