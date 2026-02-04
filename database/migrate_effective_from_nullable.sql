-- Migration: Make effective_from nullable in product_costs table
-- This allows NULL values to be inserted instead of '0000-00-00'

ALTER TABLE product_costs 
MODIFY COLUMN effective_from DATETIME NULL;

-- Also make effective_from nullable in product_sector_discounts for consistency
ALTER TABLE product_sector_discounts 
MODIFY COLUMN effective_from DATETIME NULL;

