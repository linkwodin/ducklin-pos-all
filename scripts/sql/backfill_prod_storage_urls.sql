-- Rewire cloned UAT storage URLs to the production GCS bucket.
-- Run against pos_system on ducklin-uk-prod after uploads rsync.
--
-- Usage (via separate-prod-storage.sh):
--   UAT_BUCKET=ducklin-uk-uat-pos-uploads PROD_BUCKET=ducklin-uk-prod-pos-uploads \
--     mysql ... < scripts/sql/backfill_prod_storage_urls.sql

SET @uat_bucket = 'ducklin-uk-uat-pos-uploads';
SET @prod_bucket = 'ducklin-uk-prod-pos-uploads';

-- users.icon_url
UPDATE users
SET icon_url = REPLACE(icon_url, @uat_bucket, @prod_bucket)
WHERE icon_url LIKE CONCAT('%', @uat_bucket, '%');

-- product_lines.image_url, products.image_url
UPDATE product_lines
SET image_url = REPLACE(image_url, @uat_bucket, @prod_bucket)
WHERE image_url LIKE CONCAT('%', @uat_bucket, '%');

UPDATE products
SET image_url = REPLACE(image_url, @uat_bucket, @prod_bucket)
WHERE image_url LIKE CONCAT('%', @uat_bucket, '%');

-- wholesale documents and payment proofs
UPDATE wholesale_order_documents
SET file_url = REPLACE(file_url, @uat_bucket, @prod_bucket)
WHERE file_url LIKE CONCAT('%', @uat_bucket, '%');

UPDATE wholesale_orders
SET payment_proof_url = REPLACE(payment_proof_url, @uat_bucket, @prod_bucket)
WHERE payment_proof_url LIKE CONCAT('%', @uat_bucket, '%');

UPDATE shipments
SET delivery_note_pdf_url = REPLACE(delivery_note_pdf_url, @uat_bucket, @prod_bucket)
WHERE delivery_note_pdf_url LIKE CONCAT('%', @uat_bucket, '%');

UPDATE shipments
SET signed_delivery_note_pdf_url = REPLACE(signed_delivery_note_pdf_url, @uat_bucket, @prod_bucket)
WHERE signed_delivery_note_pdf_url LIKE CONCAT('%', @uat_bucket, '%');

-- audit log JSON may embed file_url / previous_file_url from UAT
UPDATE audit_logs
SET changes = REPLACE(changes, @uat_bucket, @prod_bucket)
WHERE changes LIKE CONCAT('%', @uat_bucket, '%');
