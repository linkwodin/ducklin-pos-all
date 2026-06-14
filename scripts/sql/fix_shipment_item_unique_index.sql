-- Fix shipment_items unique key: one row per (shipment, order line), not globally per order line.
-- Required for partial assign / remainder to a 2nd store shipment.
-- The old unique index on wholesale_order_item_id alone is used by a FK, so add a replacement index first.

ALTER TABLE shipment_items ADD INDEX idx_shipment_items_wo_item (wholesale_order_item_id);
ALTER TABLE shipment_items DROP INDEX idx_shipment_wo_item;
ALTER TABLE shipment_items ADD UNIQUE INDEX idx_shipment_wo_item (shipment_id, wholesale_order_item_id);
