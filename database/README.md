# Database Schema

MySQL database schema for the POS system.

## Setup

1. **Create the database:**
   ```sql
   CREATE DATABASE pos_system;
   ```

2. **Run the schema:**
   ```bash
   mysql -u root -p pos_system < schema.sql
   ```

   Or from MySQL client:
   ```sql
   USE pos_system;
   SOURCE schema.sql;
   ```

## Database Structure

### Core Tables

- **users** - System users (management, POS users, supervisors)
- **stores** - Physical store locations
- **pos_devices** - POS device/computer registrations
- **user_stores** - User-store assignments (many-to-many)

### Product Tables

- **products** - Product catalog
- **product_costs** - Product cost configurations with history
- **product_sector_discounts** - Discount rates by sector
- **price_history** - Historical price data for trend analysis

### Inventory Tables

- **stock** - Current stock levels per store
- **restock_orders** - Re-stock order tracking
- **restock_order_items** - Items in re-stock orders

### Order Tables

- **orders** - POS orders
- **order_items** - Items in orders

### System Tables

- **sectors** - Customer sectors (wholesaler, restaurant, etc.)
- **audit_logs** - System audit trail

## Key Features

### Historical Data

- **product_costs**: Tracks cost changes over time with `effective_from` and `effective_to` dates
- **product_sector_discounts**: Tracks discount changes with effective dates
- **price_history**: Records price changes for trend graphs

### Soft Deletes

- Products, sectors, users, and stores use `is_active` flag for soft deletion
- Historical data is preserved

### Relationships

- Products can have multiple cost configurations (historical)
- Products can have discounts per sector
- Users can be assigned to multiple stores
- Orders link to users, stores, and sectors

## Indexes

The schema includes indexes on:
- Foreign keys
- Frequently queried fields (barcode, SKU, order_number, etc.)
- Date fields for time-based queries

## Data Migration

When updating the schema:

1. **Backup existing data:**
   ```bash
   mysqldump -u root -p pos_system > backup.sql
   ```

2. **Apply migrations:**
   - Review schema changes
   - Test on development database first
   - Apply to production during maintenance window

3. **Verify data integrity:**
   - Check foreign key constraints
   - Verify indexes are created
   - Test application functionality

## Initial Data

After creating the schema, you'll need to:

1. **Create initial management user** (via API or directly in database)
2. **Create at least one store**
3. **Create sectors** (wholesaler, restaurant, etc.)
4. **Add products and configure costs**

## Backup and Recovery

### Backup

```bash
mysqldump -u root -p pos_system > backup_$(date +%Y%m%d).sql
```

### Restore

```bash
mysql -u root -p pos_system < backup_20240101.sql
```

## Performance Considerations

- **Indexes**: Ensure indexes are maintained for frequently queried fields
- **Partitioning**: Consider partitioning `price_history` and `audit_logs` by date for large datasets
- **Archiving**: Archive old `price_history` and `audit_logs` records periodically

## Security

- Use strong passwords for database users
- Grant minimal required permissions
- Enable SSL for remote connections
- Regular security updates
- Backup encryption

## Connection String Format

```
mysql://username:password@host:port/database
```

Example:
```
mysql://pos_user:secure_password@localhost:3306/pos_system
```

