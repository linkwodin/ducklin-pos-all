-- Backfill shipment item quantities from order line qty for legacy rows.
UPDATE shipment_items si
INNER JOIN wholesale_order_items woi ON woi.id = si.wholesale_order_item_id
SET si.quantity = woi.quantity
WHERE si.quantity IS NULL OR si.quantity = 0;
