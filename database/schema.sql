-- POS System Database Schema
-- MySQL Database for Backend Management System

-- Users table
CREATE TABLE users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    pin_hash VARCHAR(255),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255),
    role ENUM('management', 'pos_user', 'supervisor') NOT NULL,
    icon_url VARCHAR(500),
    icon_color VARCHAR(7), -- Hex color code
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_username (username),
    INDEX idx_role (role)
);

-- Stores table
CREATE TABLE stores (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(255) NOT NULL,
    address TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- POS Devices table
CREATE TABLE pos_devices (
    id INT PRIMARY KEY AUTO_INCREMENT,
    device_code VARCHAR(100) UNIQUE NOT NULL,
    store_id INT NOT NULL,
    device_name VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE,
    INDEX idx_device_code (device_code),
    INDEX idx_store_id (store_id)
);

-- User-Store assignments
CREATE TABLE user_stores (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    store_id INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE,
    UNIQUE KEY unique_user_store (user_id, store_id)
);

-- Sectors table (wholesaler, wholesale to restaurant, etc.)
CREATE TABLE sectors (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Products table
CREATE TABLE products (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(255) NOT NULL,
    name_chinese VARCHAR(255),
    barcode VARCHAR(100) UNIQUE,
    sku VARCHAR(100) UNIQUE,
    category VARCHAR(100),
    image_url VARCHAR(500),
    unit_type ENUM('quantity', 'weight') NOT NULL DEFAULT 'quantity',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_barcode (barcode),
    INDEX idx_sku (sku),
    INDEX idx_category (category),
    INDEX idx_is_active (is_active)
);

-- Product Cost Configuration (based on Excel structure)
CREATE TABLE product_costs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    product_id INT NOT NULL,
    exchange_rate DECIMAL(10, 4) NOT NULL,
    purchasing_cost_hkd DECIMAL(10, 2),
    purchasing_cost_gbp DECIMAL(10, 2),
    unit_weight_g INT NOT NULL, -- Unit weight in grams
    purchasing_cost_buffer_percent DECIMAL(5, 2) DEFAULT 0,
    cost_buffer_gbp DECIMAL(10, 2) DEFAULT 0,
    adjusted_purchasing_cost_gbp DECIMAL(10, 2),
    weight_g INT NOT NULL, -- Product weight in grams
    weight_buffer_percent DECIMAL(5, 2) DEFAULT 0,
    freight_rate_hkd_per_kg DECIMAL(10, 2) NOT NULL,
    freight_buffer_hkd DECIMAL(10, 2) DEFAULT 0,
    freight_hkd DECIMAL(10, 2),
    freight_gbp DECIMAL(10, 2),
    import_duty_percent DECIMAL(5, 2) DEFAULT 0,
    import_duty_gbp DECIMAL(10, 2) DEFAULT 0,
    packaging_gbp DECIMAL(10, 2) DEFAULT 0,
    wholesale_cost_gbp DECIMAL(10, 2) NOT NULL,
    effective_from TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    effective_to TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
    INDEX idx_product_id (product_id),
    INDEX idx_effective_from (effective_from),
    INDEX idx_effective_to (effective_to)
);

-- Product-Sector Discounts
CREATE TABLE product_sector_discounts (
    id INT PRIMARY KEY AUTO_INCREMENT,
    product_id INT NOT NULL,
    sector_id INT NOT NULL,
    discount_percent DECIMAL(5, 2) NOT NULL DEFAULT 0,
    effective_from TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    effective_to TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
    FOREIGN KEY (sector_id) REFERENCES sectors(id) ON DELETE CASCADE,
    UNIQUE KEY unique_product_sector (product_id, sector_id, effective_from),
    INDEX idx_product_id (product_id),
    INDEX idx_sector_id (sector_id)
);

-- Stock table
CREATE TABLE stock (
    id INT PRIMARY KEY AUTO_INCREMENT,
    product_id INT NOT NULL,
    store_id INT NOT NULL,
    quantity DECIMAL(10, 3) NOT NULL DEFAULT 0, -- Supports weight-based products
    low_stock_threshold DECIMAL(10, 3) DEFAULT 0,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
    FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE,
    UNIQUE KEY unique_product_store (product_id, store_id),
    INDEX idx_store_id (store_id),
    INDEX idx_low_stock (store_id, quantity, low_stock_threshold)
);

-- Re-stock Orders
CREATE TABLE restock_orders (
    id INT PRIMARY KEY AUTO_INCREMENT,
    store_id INT NOT NULL,
    initiated_by INT NOT NULL,
    tracking_number VARCHAR(255),
    status ENUM('initiated', 'in_transit', 'received', 'cancelled') DEFAULT 'initiated',
    initiated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    received_at TIMESTAMP NULL,
    notes TEXT,
    FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE,
    FOREIGN KEY (initiated_by) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_store_id (store_id),
    INDEX idx_status (status),
    INDEX idx_tracking_number (tracking_number)
);

-- Re-stock Order Items
CREATE TABLE restock_order_items (
    id INT PRIMARY KEY AUTO_INCREMENT,
    restock_order_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity DECIMAL(10, 3) NOT NULL,
    FOREIGN KEY (restock_order_id) REFERENCES restock_orders(id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
    INDEX idx_restock_order_id (restock_order_id)
);

-- Orders (from POS)
CREATE TABLE orders (
    id INT PRIMARY KEY AUTO_INCREMENT,
    order_number VARCHAR(100) UNIQUE NOT NULL,
    store_id INT NOT NULL,
    user_id INT NOT NULL,
    device_code VARCHAR(100),
    sector_id INT,
    subtotal DECIMAL(10, 2) NOT NULL,
    discount_amount DECIMAL(10, 2) DEFAULT 0,
    total_amount DECIMAL(10, 2) NOT NULL,
    status ENUM('pending', 'paid', 'completed', 'cancelled') DEFAULT 'pending',
    qr_code_data TEXT, -- JSON data for QR code
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    paid_at TIMESTAMP NULL,
    completed_at TIMESTAMP NULL,
    FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (sector_id) REFERENCES sectors(id) ON DELETE SET NULL,
    INDEX idx_order_number (order_number),
    INDEX idx_store_id (store_id),
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at)
);

-- Order Items
CREATE TABLE order_items (
    id INT PRIMARY KEY AUTO_INCREMENT,
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity DECIMAL(10, 3) NOT NULL,
    unit_price DECIMAL(10, 2) NOT NULL,
    discount_percent DECIMAL(5, 2) DEFAULT 0,
    discount_amount DECIMAL(10, 2) DEFAULT 0,
    line_total DECIMAL(10, 2) NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
    INDEX idx_order_id (order_id)
);

-- Price History (for trend graphs)
CREATE TABLE price_history (
    id INT PRIMARY KEY AUTO_INCREMENT,
    product_id INT NOT NULL,
    sector_id INT,
    wholesale_cost_gbp DECIMAL(10, 2) NOT NULL,
    discount_percent DECIMAL(5, 2) DEFAULT 0,
    final_price_gbp DECIMAL(10, 2) NOT NULL,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
    FOREIGN KEY (sector_id) REFERENCES sectors(id) ON DELETE SET NULL,
    INDEX idx_product_id (product_id),
    INDEX idx_sector_id (sector_id),
    INDEX idx_recorded_at (recorded_at)
);

-- Audit Log
CREATE TABLE audit_logs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50),
    entity_id INT,
    changes JSON,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_user_id (user_id),
    INDEX idx_action (action),
    INDEX idx_entity_type (entity_type),
    INDEX idx_created_at (created_at)
);

