import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

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
    return await openDatabase(
      dbPath,
      version: 5, // Incremented version to add picked_up_at column to orders
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
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
    
    print('DatabaseService: Database upgrade completed');
  }

  Future<String> _getDatabasePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return path.join(directory.path, 'pos_system.db');
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
        is_active INTEGER DEFAULT 1,
        created_at TEXT,
        updated_at TEXT,
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

    // Create indexes
    await db.execute('CREATE INDEX idx_products_barcode ON products(barcode)');
    await db.execute('CREATE INDEX idx_products_category ON products(category)');
    await db.execute('CREATE INDEX idx_orders_synced ON orders(synced)');
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
        'barcode': product['barcode'],
        'sku': product['sku'],
        'category': product['category'],
        'image_url': product['image_url'],
        'unit_type': product['unit_type'],
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
    final db = await database;
    final results = await db.query(
      'products',
      where: 'barcode = ? AND is_active = 1',
      whereArgs: [barcode],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  // Stock methods
  Future<void> updateStock(int productId, int storeId, double quantity) async {
    final db = await database;
    await db.insert(
      'stock',
      {
        'product_id': productId,
        'store_id': storeId,
        'quantity': quantity,
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

  // Order methods
  Future<int> saveOrder(Map<String, dynamic> order) async {
    final db = await database;
    return await db.insert('orders', order);
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
    final db = await database;
    await db.close();
  }
}

