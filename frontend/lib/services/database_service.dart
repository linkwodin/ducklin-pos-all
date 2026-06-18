import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../config/api_config.dart';
import '../utils/product_barcode.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDatabase();
    return _database!;
  }

  Future<Database> initDatabase() async {
    // Initialize FFI for desktop platforms
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    // Get database path
    final dbPath = await _getDatabasePath();

    // Open database
    // Note: SQLite encryption requires SQLCipher extension
    // For now, using unencrypted database. Encryption can be added later with SQLCipher
    final db = await openDatabase(
      dbPath,
      version: 16, // v16: order_items.unit_type on fresh installs; v15: nullable barcodes
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
    
    // Ensure schema is correct (safety check for missing columns)
    await _ensureSchema(db);
    
    return db;
  }

  // Ensure database schema has all required columns (safety check)
  Future<void> _ensureSchema(Database db) async {
    try {
      // Check if pos_price column exists in products table
      final result = await db.rawQuery('PRAGMA table_info(products)');
      final hasPosPrice = result.any((column) => column['name'] == 'pos_price');
      
      if (!hasPosPrice) {
        print('DatabaseService: pos_price column missing, adding it...');
        await db.execute('ALTER TABLE products ADD COLUMN pos_price REAL DEFAULT 0');
        print('DatabaseService: pos_price column added successfully');
      }
      final hasWeightPrefix = result.any((column) => column['name'] == 'weight_barcode_prefix');
      if (!hasWeightPrefix) {
        await db.execute('ALTER TABLE products ADD COLUMN weight_barcode_prefix TEXT');
      }
      final hasPriceWeightG = result.any((column) => column['name'] == 'price_weight_g');
      if (!hasPriceWeightG) {
        await db.execute('ALTER TABLE products ADD COLUMN price_weight_g REAL DEFAULT 0');
      }
      final hasCanSellByWeight = result.any((column) => column['name'] == 'can_sell_by_weight');
      if (!hasCanSellByWeight) {
        await db.execute('ALTER TABLE products ADD COLUMN can_sell_by_weight INTEGER DEFAULT 0');
      }
      final hasPrepackWeightG = result.any((column) => column['name'] == 'prepack_weight_g');
      if (!hasPrepackWeightG) {
        await db.execute('ALTER TABLE products ADD COLUMN prepack_weight_g REAL DEFAULT 0');
      }
      final hasSellByQty = result.any((column) => column['name'] == 'sell_by_qty');
      if (!hasSellByQty) {
        await db.execute('ALTER TABLE products ADD COLUMN sell_by_qty INTEGER DEFAULT 1');
      }
      final hasSellByWeight = result.any((column) => column['name'] == 'sell_by_weight');
      if (!hasSellByWeight) {
        await db.execute('ALTER TABLE products ADD COLUMN sell_by_weight INTEGER DEFAULT 0');
      }
      final hasWeightBarcode = result.any((column) => column['name'] == 'weight_barcode');
      if (!hasWeightBarcode) {
        await db.execute('ALTER TABLE products ADD COLUMN weight_barcode TEXT');
      }
      final hasProductLineId = result.any((column) => column['name'] == 'product_line_id');
      if (!hasProductLineId) {
        await db.execute('ALTER TABLE products ADD COLUMN product_line_id INTEGER DEFAULT 0');
      }
      final hasVariantLabel = result.any((column) => column['name'] == 'variant_label');
      if (!hasVariantLabel) {
        await db.execute('ALTER TABLE products ADD COLUMN variant_label TEXT');
      }
      final hasUnitsPerPack = result.any((column) => column['name'] == 'units_per_pack');
      if (!hasUnitsPerPack) {
        await db.execute('ALTER TABLE products ADD COLUMN units_per_pack REAL DEFAULT 0');
      }
      await _normalizeEmptyUniqueProductCodes(db);
      final stockInfo = await db.rawQuery('PRAGMA table_info(stock)');
      final hasWeightQty = stockInfo.any((column) => column['name'] == 'weight_quantity_g');
      if (!hasWeightQty) {
        await db.execute('ALTER TABLE stock ADD COLUMN weight_quantity_g REAL DEFAULT 0');
      }
      final hasTrackPrepacked = stockInfo.any((column) => column['name'] == 'track_prepacked');
      if (!hasTrackPrepacked) {
        await db.execute('ALTER TABLE stock ADD COLUMN track_prepacked INTEGER DEFAULT 1');
      }
      final hasTrackWeight = stockInfo.any((column) => column['name'] == 'track_weight');
      if (!hasTrackWeight) {
        await db.execute('ALTER TABLE stock ADD COLUMN track_weight INTEGER DEFAULT 0');
      }
      final orderItemsInfo = await db.rawQuery('PRAGMA table_info(order_items)');
      final hasUnitType = orderItemsInfo.any((column) => column['name'] == 'unit_type');
      if (!hasUnitType) {
        print('DatabaseService: order_items.unit_type missing, adding it...');
        await db.execute(
          "ALTER TABLE order_items ADD COLUMN unit_type TEXT NOT NULL DEFAULT 'quantity'",
        );
        print('DatabaseService: order_items.unit_type added successfully');
      }
    } catch (e) {
      print('DatabaseService: Error ensuring schema: $e');
      // Don't throw - continue with existing schema
    }
  }

  Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    print('DatabaseService: Upgrading database from version $oldVersion to $newVersion');
    
    if (oldVersion < 2) {
      // Add missing columns to users table
      try {
        await db.execute('ALTER TABLE users ADD COLUMN email TEXT');
      } catch (e) {
        print('DatabaseService: Column email may already exist: $e');
      }
      
      try {
        await db.execute('ALTER TABLE users ADD COLUMN is_active INTEGER DEFAULT 1');
      } catch (e) {
        print('DatabaseService: Column is_active may already exist: $e');
      }
      
      try {
        await db.execute('ALTER TABLE users ADD COLUMN created_at TEXT');
      } catch (e) {
        print('DatabaseService: Column created_at may already exist: $e');
      }
      
      try {
        await db.execute('ALTER TABLE users ADD COLUMN updated_at TEXT');
      } catch (e) {
        print('DatabaseService: Column updated_at may already exist: $e');
      }
    }
    
    if (oldVersion < 3) {
      // Add missing columns to products table
      try {
        await db.execute('ALTER TABLE products ADD COLUMN created_at TEXT');
      } catch (e) {
        print('DatabaseService: Column products.created_at may already exist: $e');
      }
      
      try {
        await db.execute('ALTER TABLE products ADD COLUMN updated_at TEXT');
      } catch (e) {
        print('DatabaseService: Column products.updated_at may already exist: $e');
      }
      
      print('DatabaseService: Products table upgrade completed');
    }
    
    if (oldVersion < 4) {
      // Add pos_price column to products table
      try {
        await db.execute('ALTER TABLE products ADD COLUMN pos_price REAL DEFAULT 0');
      } catch (e) {
        print('DatabaseService: Column products.pos_price may already exist: $e');
      }
      
      print('DatabaseService: Products table upgrade to v4 completed');
    }
    
    if (oldVersion < 5) {
      // Add picked_up_at column to orders table
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN picked_up_at INTEGER');
      } catch (e) {
        print('DatabaseService: Column orders.picked_up_at may already exist: $e');
      }
      
      print('DatabaseService: Orders table upgrade to v5 completed');
    }

    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE order_items ADD COLUMN unit_type TEXT DEFAULT \'quantity\'');
      } catch (e) {
        print('DatabaseService: Column order_items.unit_type may already exist: $e');
      }
      print('DatabaseService: Orders table upgrade to v6 completed');
    }

    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pending_stocktakes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          store_id INTEGER NOT NULL,
          type TEXT NOT NULL,
          reason TEXT,
          created_at INTEGER,
          synced INTEGER DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pending_stocktake_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          stocktake_id INTEGER NOT NULL,
          product_id INTEGER NOT NULL,
          quantity REAL NOT NULL,
          FOREIGN KEY (stocktake_id) REFERENCES pending_stocktakes(id)
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pending_stocktakes_synced ON pending_stocktakes(synced)');
      print('DatabaseService: Database upgrade to v7 (pending_stocktakes) completed');
    }

    if (oldVersion < 8) {
      try {
        await db.execute('ALTER TABLE pending_stocktake_items ADD COLUMN reason TEXT');
      } catch (e) {
        print('DatabaseService: Column pending_stocktake_items.reason may already exist: $e');
      }
      print('DatabaseService: Database upgrade to v8 (pending_stocktake_items.reason) completed');
    }

    if (oldVersion < 9) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pending_user_activity_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL,
          store_id INTEGER,
          event_type TEXT NOT NULL,
          occurred_at TEXT NOT NULL,
          skip_reason TEXT,
          synced INTEGER DEFAULT 0
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pending_user_activity_events_synced ON pending_user_activity_events(synced)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_pending_user_activity_events_user ON pending_user_activity_events(user_id)');
      print('DatabaseService: Database upgrade to v9 (pending_user_activity_events) completed');
    }

    if (oldVersion < 10) {
      try {
        await db.execute('ALTER TABLE products ADD COLUMN weight_barcode_prefix TEXT');
      } catch (e) {
        print('DatabaseService: Column products.weight_barcode_prefix may already exist: $e');
      }
      print('DatabaseService: Database upgrade to v10 (products.weight_barcode_prefix) completed');
    }

    if (oldVersion < 11) {
      try {
        await db.execute('ALTER TABLE products ADD COLUMN price_weight_g REAL DEFAULT 0');
      } catch (e) {
        print('DatabaseService: Column products.price_weight_g may already exist: $e');
      }
      print('DatabaseService: Database upgrade to v11 (products.price_weight_g) completed');
    }
    
    if (oldVersion < 12) {
      try {
        await db.execute('ALTER TABLE products ADD COLUMN can_sell_by_weight INTEGER DEFAULT 0');
      } catch (e) {
        print('DatabaseService: Column products.can_sell_by_weight may already exist: $e');
      }
      try {
        await db.execute('ALTER TABLE products ADD COLUMN prepack_weight_g REAL DEFAULT 0');
      } catch (e) {
        print('DatabaseService: Column products.prepack_weight_g may already exist: $e');
      }
      try {
        await db.execute('ALTER TABLE stock ADD COLUMN weight_quantity_g REAL DEFAULT 0');
      } catch (e) {
        print('DatabaseService: Column stock.weight_quantity_g may already exist: $e');
      }
      try {
        await db.execute('ALTER TABLE stock ADD COLUMN track_prepacked INTEGER DEFAULT 1');
      } catch (e) {
        print('DatabaseService: Column stock.track_prepacked may already exist: $e');
      }
      try {
        await db.execute('ALTER TABLE stock ADD COLUMN track_weight INTEGER DEFAULT 0');
      } catch (e) {
        print('DatabaseService: Column stock.track_weight may already exist: $e');
      }
      try {
        await db.execute('ALTER TABLE pending_stocktake_items ADD COLUMN weight_quantity_g REAL');
      } catch (e) {
        print('DatabaseService: Column pending_stocktake_items.weight_quantity_g may already exist: $e');
      }
      print('DatabaseService: Database upgrade to v12 (dual inventory) completed');
    }

    if (oldVersion < 13) {
      try {
        await db.execute('ALTER TABLE products ADD COLUMN sell_by_qty INTEGER DEFAULT 1');
      } catch (e) {
        print('DatabaseService: Column products.sell_by_qty may already exist: $e');
      }
      try {
        await db.execute('ALTER TABLE products ADD COLUMN sell_by_weight INTEGER DEFAULT 0');
      } catch (e) {
        print('DatabaseService: Column products.sell_by_weight may already exist: $e');
      }
      try {
        await db.execute('ALTER TABLE products ADD COLUMN weight_barcode TEXT');
      } catch (e) {
        print('DatabaseService: Column products.weight_barcode may already exist: $e');
      }
      print('DatabaseService: Database upgrade to v13 (sell_by_qty/weight barcodes) completed');
    }

    if (oldVersion < 14) {
      for (final col in [
        'ALTER TABLE products ADD COLUMN product_line_id INTEGER DEFAULT 0',
        'ALTER TABLE products ADD COLUMN variant_label TEXT',
        'ALTER TABLE products ADD COLUMN units_per_pack REAL DEFAULT 0',
      ]) {
        try {
          await db.execute(col);
        } catch (e) {
          print('DatabaseService: v14 column may already exist: $e');
        }
      }
      print('DatabaseService: Database upgrade to v14 (product lines) completed');
    }

    if (oldVersion < 15) {
      await _normalizeEmptyUniqueProductCodes(db);
      print('DatabaseService: Database upgrade to v15 (nullable product barcodes) completed');
    }

    if (oldVersion < 16) {
      try {
        await db.execute(
          "ALTER TABLE order_items ADD COLUMN unit_type TEXT NOT NULL DEFAULT 'quantity'",
        );
      } catch (e) {
        print('DatabaseService: Column order_items.unit_type may already exist: $e');
      }
      print('DatabaseService: Database upgrade to v16 (order_items.unit_type) completed');
    }
    
    try {
      await db.execute('ALTER TABLE products ADD COLUMN pos_price REAL DEFAULT 0');
      print('DatabaseService: Added pos_price column (safety check)');
    } catch (e) {
      // Column already exists, which is fine
      print('DatabaseService: pos_price column already exists (safety check)');
    }
    
    print('DatabaseService: Database upgrade completed');
  }

  Future<String> _getDatabasePath() async {
    final directory = await getApplicationDocumentsDirectory();
    // Use env-specific DB so UAT/production builds do not reuse dev/test data
    final env = ApiConfig.environment.toLowerCase();
    final dbName = env == 'uat' || env == 'production' || env == 'prod'
        ? 'pos_system_$env.db'
        : 'pos_system.db';
    return path.join(directory.path, dbName);
  }

  Future<void> _createDatabase(Database db, int version) async {
    // Users table
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        email TEXT,
        role TEXT NOT NULL,
        icon_url TEXT,
        icon_color TEXT,
        pin_hash TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT,
        updated_at TEXT,
        synced_at INTEGER
      )
    ''');

    // Products table
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        name_chinese TEXT,
        barcode TEXT UNIQUE,
        sku TEXT UNIQUE,
        category TEXT,
        image_url TEXT,
        unit_type TEXT NOT NULL,
        weight_barcode_prefix TEXT,
        price_weight_g REAL DEFAULT 0,
        can_sell_by_weight INTEGER DEFAULT 0,
        prepack_weight_g REAL DEFAULT 0,
        sell_by_qty INTEGER DEFAULT 1,
        sell_by_weight INTEGER DEFAULT 0,
        weight_barcode TEXT,
        product_line_id INTEGER DEFAULT 0,
        variant_label TEXT,
        units_per_pack REAL DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        created_at TEXT,
        updated_at TEXT,
        pos_price REAL DEFAULT 0,
        synced_at INTEGER
      )
    ''');

    // Product Costs table
    await db.execute('''
      CREATE TABLE product_costs (
        id INTEGER PRIMARY KEY,
        product_id INTEGER NOT NULL,
        wholesale_cost_gbp REAL NOT NULL,
        effective_from INTEGER,
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');

    // Product Discounts table
    await db.execute('''
      CREATE TABLE product_discounts (
        id INTEGER PRIMARY KEY,
        product_id INTEGER NOT NULL,
        sector_id INTEGER,
        discount_percent REAL DEFAULT 0,
        effective_from INTEGER,
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');

    // Stock table
    await db.execute('''
      CREATE TABLE stock (
        id INTEGER PRIMARY KEY,
        product_id INTEGER NOT NULL,
        store_id INTEGER NOT NULL,
        quantity REAL NOT NULL DEFAULT 0,
        weight_quantity_g REAL DEFAULT 0,
        track_prepacked INTEGER DEFAULT 1,
        track_weight INTEGER DEFAULT 0,
        last_updated INTEGER,
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');

    // Orders table (for offline storage)
    await db.execute('''
      CREATE TABLE orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_number TEXT UNIQUE NOT NULL,
        store_id INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        sector_id INTEGER,
        subtotal REAL NOT NULL,
        discount_amount REAL DEFAULT 0,
        total_amount REAL NOT NULL,
        status TEXT DEFAULT 'pending',
        qr_code_data TEXT,
        created_at INTEGER,
        picked_up_at INTEGER,
        synced INTEGER DEFAULT 0
      )
    ''');

    // Order Items table
    await db.execute('''
      CREATE TABLE order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        quantity REAL NOT NULL,
        unit_type TEXT NOT NULL DEFAULT 'quantity',
        unit_price REAL NOT NULL,
        discount_percent REAL DEFAULT 0,
        discount_amount REAL DEFAULT 0,
        line_total REAL NOT NULL,
        FOREIGN KEY (order_id) REFERENCES orders(id),
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');

    // Device info table
    await db.execute('''
      CREATE TABLE device_info (
        id INTEGER PRIMARY KEY,
        device_code TEXT UNIQUE NOT NULL,
        store_id INTEGER,
        last_sync INTEGER
      )
    ''');

    // Pending stocktakes (offline stocktake sync)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_stocktakes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        store_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        reason TEXT,
        created_at INTEGER,
        synced INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_stocktake_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stocktake_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        quantity REAL NOT NULL,
        reason TEXT,
        FOREIGN KEY (stocktake_id) REFERENCES pending_stocktakes(id)
      )
    ''');

    // Create indexes
    await db.execute('CREATE INDEX idx_products_barcode ON products(barcode)');
    await db.execute('CREATE INDEX idx_products_category ON products(category)');
    await db.execute('CREATE INDEX idx_orders_synced ON orders(synced)');
    await db.execute('CREATE INDEX idx_pending_stocktakes_synced ON pending_stocktakes(synced)');

    // Pending user activity events (offline first_login, logout, stocktake done/skipped → sync when online)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_user_activity_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        store_id INTEGER,
        event_type TEXT NOT NULL,
        occurred_at TEXT NOT NULL,
        skip_reason TEXT,
        synced INTEGER DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pending_user_activity_events_synced ON pending_user_activity_events(synced)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pending_user_activity_events_user ON pending_user_activity_events(user_id)');
  }

  // User methods
  Future<void> saveUsers(List<Map<String, dynamic>> users) async {
    final db = await database;
    final batch = db.batch();
    
    for (var user in users) {
      // Map and filter user data to match database schema
      final userData = <String, dynamic>{
        'id': user['id'],
        'username': user['username'],
        'first_name': user['first_name'],
        'last_name': user['last_name'],
        'email': user['email'] ?? '',
        'role': user['role'],
        'icon_url': user['icon_url'] ?? '',
        'icon_color': user['icon_color'] ?? '',
        'pin_hash': user['pin_hash'] ?? '',
        'is_active': (user['is_active'] ?? true) ? 1 : 0,
        'created_at': user['created_at']?.toString() ?? '',
        'updated_at': user['updated_at']?.toString() ?? '',
        'synced_at': DateTime.now().millisecondsSinceEpoch,
      };
      
      batch.insert(
        'users',
        userData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    
    await batch.commit(noResult: true);
  }

  /// Remove local users whose id is not in [ids] (e.g. after sync: keep only users from server).
  Future<void> deleteUsersNotInIds(Iterable<dynamic> ids) async {
    final idList = ids.map((e) => e is int ? e : (e as num).toInt()).toList();
    if (idList.isEmpty) {
      final db = await database;
      await db.delete('users');
      return;
    }
    final placeholders = List.filled(idList.length, '?').join(',');
    final db = await database;
    await db.delete('users', where: 'id NOT IN ($placeholders)', whereArgs: idList);
  }

  Future<List<Map<String, dynamic>>> getUsers() async {
    final db = await database;
    // Only return active users
    return await db.query(
      'users',
      where: 'is_active = 1',
      orderBy: 'first_name, last_name',
    );
  }

  Future<void> updateUserIcon(int userId, String iconUrl) async {
    final db = await database;
    await db.update(
      'users',
      {'icon_url': iconUrl, 'synced_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<void> _normalizeEmptyUniqueProductCodes(Database db) async {
    // SQLite UNIQUE treats '' as a value — only one weight variant could sync with empty barcode.
    await db.execute("UPDATE products SET barcode = NULL WHERE barcode IS NULL OR trim(barcode) = ''");
    await db.execute("UPDATE products SET sku = NULL WHERE sku IS NULL OR trim(sku) = ''");
    await db.execute(
      "UPDATE products SET weight_barcode = NULL WHERE weight_barcode IS NULL OR trim(weight_barcode) = ''",
    );
    await db.execute(
      "UPDATE products SET weight_barcode_prefix = NULL WHERE weight_barcode_prefix IS NULL OR trim(weight_barcode_prefix) = ''",
    );
  }

  static String? _nullableUniqueText(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  // Product methods
  Future<void> saveProducts(List<Map<String, dynamic>> products) async {
    final db = await database;
    final batch = db.batch();
    
    for (var product in products) {
      // Filter out nested objects and only save flat fields that exist in the schema
      final productData = <String, dynamic>{
        'id': product['id'],
        'name': product['name'],
        'name_chinese': product['name_chinese'],
        'barcode': _nullableUniqueText(product['barcode']),
        'sku': _nullableUniqueText(product['sku']),
        'category': product['category'],
        'image_url': product['image_url'],
        'unit_type': product['unit_type'],
        'weight_barcode_prefix': _nullableUniqueText(product['weight_barcode_prefix']),
        'price_weight_g': (product['price_weight_g'] as num?)?.toDouble() ?? 0.0,
        'can_sell_by_weight': (product['can_sell_by_weight'] == true || product['can_sell_by_weight'] == 1) ? 1 : 0,
        'prepack_weight_g': (product['prepack_weight_g'] as num?)?.toDouble() ?? 0.0,
        'sell_by_qty': _boolToInt(product['sell_by_qty'], defaultValue: product['unit_type'] != 'weight'),
        'sell_by_weight': _boolToInt(
          product['sell_by_weight'],
          defaultValue: product['can_sell_by_weight'] == true ||
              product['can_sell_by_weight'] == 1 ||
              product['unit_type'] == 'weight',
        ),
        'weight_barcode': _nullableUniqueText(product['weight_barcode']),
        'product_line_id': (product['product_line_id'] as num?)?.toInt() ?? 0,
        'variant_label': product['variant_label']?.toString() ?? '',
        'units_per_pack': (product['units_per_pack'] as num?)?.toDouble() ?? 0.0,
        'is_active': (product['is_active'] ?? true) ? 1 : 0,
        'created_at': product['created_at']?.toString() ?? '',
        'updated_at': product['updated_at']?.toString() ?? '',
        'pos_price': (product['pos_price'] as num?)?.toDouble() ?? 0.0, // Save POS price from backend
        'synced_at': DateTime.now().millisecondsSinceEpoch,
        // Note: current_cost and discounts are nested objects, not stored in products table
        // They can be accessed from the backend API when needed
      };
      
      batch.insert(
        'products',
        productData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    
    await batch.commit(noResult: true);
  }

  /// Remove local products whose id is not in [ids] (e.g. after sync: keep only products from server).
  /// Also removes dependent rows in product_costs, product_discounts, stock.
  Future<void> deleteProductsNotInIds(Iterable<dynamic> ids) async {
    final idList = ids.map((e) => e is int ? e : (e as num).toInt()).toList();
    final db = await database;
    if (idList.isEmpty) {
      await db.delete('stock');
      await db.delete('product_costs');
      await db.delete('product_discounts');
      await db.delete('products');
      return;
    }
    final placeholders = List.filled(idList.length, '?').join(',');
    await db.delete('stock', where: 'product_id NOT IN ($placeholders)', whereArgs: idList);
    await db.delete('product_costs', where: 'product_id NOT IN ($placeholders)', whereArgs: idList);
    await db.delete('product_discounts', where: 'product_id NOT IN ($placeholders)', whereArgs: idList);
    await db.delete('products', where: 'id NOT IN ($placeholders)', whereArgs: idList);
  }

  Future<List<Map<String, dynamic>>> getProducts({String? category}) async {
    final db = await database;
    if (category != null) {
      return await db.query(
        'products',
        where: 'category = ? AND is_active = 1',
        whereArgs: [category],
        orderBy: 'name',
      );
    }
    return await db.query('products', where: 'is_active = 1', orderBy: 'name');
  }

  Future<Map<String, dynamic>?> getProductByBarcode(String barcode) async {
    final scan = await resolveProductScan(barcode);
    return scan;
  }

  /// Lookup product by qty, weight, or weight-prefix barcode; sets `_scan_mode`.
  Future<Map<String, dynamic>?> resolveProductScan(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return null;
    final products = (await getProducts()).map(normalizeProductRow).toList();
    return resolveProductScanFromList(code, products);
  }

  static int _boolToInt(dynamic value, {required bool defaultValue}) {
    if (value == null) return defaultValue ? 1 : 0;
    if (value == true || value == 1) return 1;
    return 0;
  }

  Future<Map<String, dynamic>?> getProductById(int productId) async {
    final db = await database;
    final results = await db.query(
      'products',
      where: 'id = ? AND is_active = 1',
      whereArgs: [productId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  // Stock methods
  Future<void> updateStock(
    int productId,
    int storeId, {
    required double quantity,
    double? weightQuantityG,
    bool? trackPrepacked,
    bool? trackWeight,
  }) async {
    final db = await database;
    final existing = await getStock(productId, storeId);
    await db.insert(
      'stock',
      {
        'product_id': productId,
        'store_id': storeId,
        'quantity': quantity,
        'weight_quantity_g': weightQuantityG ?? (existing?['weight_quantity_g'] as num?)?.toDouble() ?? 0.0,
        'track_prepacked': trackPrepacked != null
            ? (trackPrepacked ? 1 : 0)
            : (existing?['track_prepacked'] as int?) ?? 1,
        'track_weight': trackWeight != null
            ? (trackWeight ? 1 : 0)
            : (existing?['track_weight'] as int?) ?? 0,
        'last_updated': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getStock(int productId, int storeId) async {
    final db = await database;
    final results = await db.query(
      'stock',
      where: 'product_id = ? AND store_id = ?',
      whereArgs: [productId, storeId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// All stock rows for a store (for offline display when API is unavailable).
  /// Returns list of { product_id, store_id, quantity } compatible with API shape.
  Future<List<Map<String, dynamic>>> getStoreStockLocal(int storeId) async {
    final db = await database;
    final results = await db.query(
      'stock',
      where: 'store_id = ?',
      whereArgs: [storeId],
    );
    return results
        .map((row) => {
              'product_id': row['product_id'],
              'store_id': row['store_id'],
              'quantity': (row['quantity'] as num?)?.toDouble() ?? 0.0,
              'weight_quantity_g': (row['weight_quantity_g'] as num?)?.toDouble() ?? 0.0,
              'track_prepacked': (row['track_prepacked'] as int?) ?? 1,
              'track_weight': (row['track_weight'] as int?) ?? 0,
            })
        .toList();
  }

  // Order methods
  Future<int> saveOrder(Map<String, dynamic> order) async {
    final db = await database;
    return await db.insert('orders', order);
  }

  Future<void> updateOrderNumber(int orderId, String orderNumber) async {
    final db = await database;
    await db.update('orders', {'order_number': orderNumber}, where: 'id = ?', whereArgs: [orderId]);
  }

  /// Update order status and optionally picked_up_at (for offline pickup/cancel).
  /// Use order_number to find the order; returns true if a row was updated.
  Future<bool> updateOrderStatusByOrderNumber(
    String orderNumber, {
    required String status,
    int? pickedUpAtMillis,
  }) async {
    final order = await getOrderByOrderNumber(orderNumber);
    if (order == null) return false;
    final db = await database;
    final updates = <String, dynamic>{'status': status};
    if (pickedUpAtMillis != null) updates['picked_up_at'] = pickedUpAtMillis;
    final n = await db.update(
      'orders',
      updates,
      where: 'order_number = ?',
      whereArgs: [orderNumber],
    );
    return n > 0;
  }

  /// Get order by order_number (for offline order details).
  Future<Map<String, dynamic>?> getOrderByOrderNumber(String orderNumber) async {
    final db = await database;
    final rows = await db.query(
      'orders',
      where: 'order_number = ?',
      whereArgs: [orderNumber],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<List<Map<String, dynamic>>> getOrderItems(int orderId) async {
    final db = await database;
    return await db.query('order_items', where: 'order_id = ?', whereArgs: [orderId]);
  }

  /// Get order with items for display (offline). Enriches items with product name from products table.
  Future<Map<String, dynamic>?> getOrderWithItemsByOrderNumber(String orderNumber) async {
    final order = await getOrderByOrderNumber(orderNumber);
    if (order == null) return null;
    final orderId = order['id'] as int;
    final items = await getOrderItems(orderId);
    final db = await database;
    final enrichedItems = <Map<String, dynamic>>[];
    for (final item in items) {
      final productId = item['product_id'];
      List<Map<String, dynamic>> productRows = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      final productRow = productRows.isNotEmpty ? productRows.first : <String, dynamic>{};
      final productName = productRow['name'] as String? ?? '';
      final nameChinese = productRow['name_chinese'] as String?;
      enrichedItems.add({
        ...item,
        'product': {
          'id': productId,
          'name': productName,
          if (nameChinese != null) 'name_chinese': nameChinese,
          'unit_type': productRow['unit_type'] ?? item['unit_type'] ?? 'quantity',
          if (productRow['barcode'] != null) 'barcode': productRow['barcode'],
          if (productRow['weight_barcode_prefix'] != null)
            'weight_barcode_prefix': productRow['weight_barcode_prefix'],
          if (productRow['price_weight_g'] != null) 'price_weight_g': productRow['price_weight_g'],
        },
      });
    }
    return {
      ...order,
      'items': enrichedItems,
      'created_at': order['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(order['created_at'] as int).toUtc().toIso8601String()
          : null,
    };
  }

  Future<int> getPendingOrdersCount() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM orders WHERE synced = 0');
    return (r.first['c'] as int?) ?? 0;
  }

  /// Count of orders with the given status (e.g. 'pending' for pending completion).
  Future<int> getOrdersCountByStatus(String status) async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) as c FROM orders WHERE status = ?',
      [status],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> saveOrderItems(int orderId, List<Map<String, dynamic>> items) async {
    final db = await database;
    final batch = db.batch();
    
    for (var item in items) {
      batch.insert('order_items', {
        ...item,
        'order_id': orderId,
      });
    }
    
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getPendingOrders() async {
    final db = await database;
    return await db.query(
      'orders',
      where: 'synced = 0',
      orderBy: 'created_at DESC',
    );
  }

  Future<void> markOrderSynced(int orderId) async {
    final db = await database;
    await db.update('orders', {'synced': 1}, where: 'id = ?', whereArgs: [orderId]);
  }

  // Pending stocktakes (offline stocktake → sync when online)
  Future<int> savePendingStocktake({
    required int storeId,
    required String type,
    required String reason,
    required List<Map<String, dynamic>> items,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.insert('pending_stocktakes', {
      'store_id': storeId,
      'type': type,
      'reason': reason,
      'created_at': now,
      'synced': 0,
    });
    for (final item in items) {
      await db.insert('pending_stocktake_items', {
        'stocktake_id': id,
        'product_id': item['product_id'],
        'quantity': (item['quantity'] as num).toDouble(),
        if (item['weight_quantity_g'] != null)
          'weight_quantity_g': (item['weight_quantity_g'] as num).toDouble(),
        if (item['reason'] != null) 'reason': item['reason'] as String?,
      });
    }
    return id as int;
  }

  Future<List<Map<String, dynamic>>> getPendingStocktakes() async {
    final db = await database;
    return await db.query(
      'pending_stocktakes',
      where: 'synced = 0',
      orderBy: 'created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getPendingStocktakeItems(int stocktakeId) async {
    final db = await database;
    return await db.query(
      'pending_stocktake_items',
      where: 'stocktake_id = ?',
      whereArgs: [stocktakeId],
    );
  }

  Future<void> markStocktakeSynced(int stocktakeId) async {
    final db = await database;
    await db.update('pending_stocktakes', {'synced': 1}, where: 'id = ?', whereArgs: [stocktakeId]);
  }

  Future<int> getPendingStocktakeCount() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM pending_stocktakes WHERE synced = 0');
    return (r.first['c'] as int?) ?? 0;
  }

  // Pending user activity events (offline first_login, logout, stocktake → sync when online)
  Future<int> savePendingUserActivityEvent({
    required int userId,
    int? storeId,
    required String eventType,
    required String occurredAt,
    String? skipReason,
  }) async {
    final db = await database;
    final id = await db.insert('pending_user_activity_events', {
      'user_id': userId,
      'store_id': storeId,
      'event_type': eventType,
      'occurred_at': occurredAt,
      'skip_reason': skipReason,
      'synced': 0,
    });
    return id as int;
  }

  /// Returns pending events for the given [userId] (so we only sync current user's events).
  Future<List<Map<String, dynamic>>> getPendingUserActivityEvents(int userId) async {
    final db = await database;
    return await db.query(
      'pending_user_activity_events',
      where: 'synced = 0 AND user_id = ?',
      whereArgs: [userId],
      orderBy: 'id ASC',
    );
  }

  Future<void> markUserActivityEventSynced(int id) async {
    final db = await database;
    await db.update('pending_user_activity_events', {'synced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getPendingUserActivityEventCount() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM pending_user_activity_events WHERE synced = 0');
    return (r.first['c'] as int?) ?? 0;
  }

  /// Today's revenue and order count from local orders (for report when offline or to merge).
  /// [storeId] optional; if null, all stores.
  /// [onlyUnsynced] if true, only count orders with synced = 0 (offline orders not yet on server).
  /// Statuses counted: paid, completed, picked_up.
  Future<Map<String, dynamic>> getTodayRevenueFromLocal(int? storeId, {bool onlyUnsynced = false}) async {
    final db = await database;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final startMs = startOfDay.millisecondsSinceEpoch;
    final endMs = endOfDay.millisecondsSinceEpoch;

    var where = 'created_at >= ? AND created_at < ? AND status IN (?, ?, ?)';
    final whereArgs = <dynamic>[startMs, endMs, 'paid', 'completed', 'picked_up'];
    if (onlyUnsynced) {
      where += ' AND synced = 0';
    }
    if (storeId != null) {
      where += ' AND store_id = ?';
      whereArgs.add(storeId);
    }

    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(total_amount), 0) as revenue, COUNT(*) as order_count FROM orders WHERE $where',
      whereArgs,
    );
    final row = r.isNotEmpty ? r.first : null;
    return {
      'revenue': (row?['revenue'] as num?)?.toDouble() ?? 0.0,
      'order_count': (row?['order_count'] as int?) ?? 0,
    };
  }

  /// Today's product sales from local orders (for report when offline or to merge).
  /// [onlyUnsynced] if true, only orders with synced = 0.
  /// Returns list of { product_id, product_name, product_name_chinese, quantity, revenue }.
  Future<List<Map<String, dynamic>>> getTodayProductSalesFromLocal(int? storeId, {bool onlyUnsynced = false}) async {
    final db = await database;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final startMs = startOfDay.millisecondsSinceEpoch;
    final endMs = endOfDay.millisecondsSinceEpoch;

    var where = 'o.created_at >= ? AND o.created_at < ? AND o.status IN (?, ?, ?)';
    final whereArgs = <dynamic>[startMs, endMs, 'paid', 'completed', 'picked_up'];
    if (onlyUnsynced) {
      where += ' AND o.synced = 0';
    }
    if (storeId != null) {
      where += ' AND o.store_id = ?';
      whereArgs.add(storeId);
    }

    final rows = await db.rawQuery(
      'SELECT oi.product_id, SUM(oi.quantity) as quantity, SUM(oi.line_total) as revenue '
      'FROM orders o INNER JOIN order_items oi ON o.id = oi.order_id '
      'WHERE $where GROUP BY oi.product_id',
      whereArgs,
    );

    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final productId = row['product_id'];
      if (productId == null) continue;
      final productRows = await db.query(
        'products',
        columns: ['name', 'name_chinese'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      final p = productRows.isNotEmpty ? productRows.first : <String, dynamic>{};
      result.add({
        'product_id': productId,
        'product_name': p['name'] ?? '',
        'product_name_chinese': p['name_chinese'],
        'quantity': (row['quantity'] as num?)?.toDouble() ?? 0.0,
        'revenue': (row['revenue'] as num?)?.toDouble() ?? 0.0,
      });
    }
    return result;
  }

  // Device methods
  Future<void> saveDeviceInfo(String deviceCode, int? storeId) async {
    final db = await database;
    await db.insert(
      'device_info',
      {
        'device_code': deviceCode,
        'store_id': storeId,
        'last_sync': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getDeviceInfo() async {
    final db = await database;
    final results = await db.query('device_info', limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  // Backup database to a timestamped file
  Future<String?> backupDatabase() async {
    try {
      final dbPath = await _getDatabasePath();
      final dbFile = File(dbPath);
      
      if (!await dbFile.exists()) {
        print('DatabaseService: No database file to backup');
        return null;
      }

      // Get backup directory
      final directory = await getApplicationDocumentsDirectory();
      final backupDir = Directory(path.join(directory.path, 'pos_system', 'backups'));
      
      // Create backup directory if it doesn't exist
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      // Create backup file with timestamp
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final backupFileName = 'pos_system_backup_$timestamp.db';
      final backupPath = path.join(backupDir.path, backupFileName);
      final backupFile = File(backupPath);

      // Copy database file to backup location
      await dbFile.copy(backupPath);
      
      print('DatabaseService: Database backed up to: $backupPath');
      return backupPath;
    } catch (e) {
      print('DatabaseService: Failed to backup database: $e');
      return null;
    }
  }

  // Get database path (public method)
  Future<String> getDatabasePath() async {
    return await _getDatabasePath();
  }

  // Clear/reset database - deletes the database file and recreates it
  Future<void> clearDatabase() async {
    try {
      // Close existing database connection
      await close();
      
      // Get database path
      final dbPath = await _getDatabasePath();
      final dbFile = File(dbPath);
      
      // Delete database file if it exists
      if (await dbFile.exists()) {
        await dbFile.delete();
        print('DatabaseService: Database file deleted');
      }
      
      // Reset database instance so it will be recreated on next access
      _database = null;
      
      print('DatabaseService: Database cleared. New database will be created on next access.');
    } catch (e) {
      print('DatabaseService: Failed to clear database: $e');
      rethrow;
    }
  }

  // Get backup directory path
  Future<String> getBackupDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    return path.join(directory.path, 'pos_system', 'backups');
  }
}

