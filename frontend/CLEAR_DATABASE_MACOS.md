# Clearing Database on macOS

This guide explains how to backup and clear the local SQLite database when launching the Flutter app on macOS.

## Database Location

The database is stored at:
```
~/Documents/pos_system.db
```

Backups are stored at:
```
~/Documents/pos_system/backups/
```

## Method 1: Launch with Clean Database (Recommended)

This will automatically backup the existing database and create a fresh one:

```bash
cd frontend
flutter run -d macos --dart-define=ENV=uat --dart-define=DEVICE_ID=DFEA26CE-2FCD-4CD6-B62A-09476BDE938B --dart-define=CLEAR_DB=true
```

## Method 2: Manual Backup and Delete

### Step 1: Backup the Database

The database is automatically backed up when you use `CLEAR_DB=true`, but you can also manually backup:

```bash
# Navigate to Documents
cd ~/Documents

# Create backup with timestamp
cp pos_system.db pos_system_backup_$(date +%Y-%m-%d_%H-%M-%S).db

# Or simple backup
cp pos_system.db pos_system_backup_manual.db
```

### Step 2: Delete the Database

```bash
rm ~/Documents/pos_system.db
```

The app will automatically create a new database when it starts.

## Method 3: Using a Script

Create a script to backup and clear:

```bash
#!/bin/bash
# backup_and_clear_db.sh

DB_PATH="$HOME/Documents/pos_system.db"
BACKUP_DIR="$HOME/Documents/pos_system/backups"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Backup if database exists
if [ -f "$DB_PATH" ]; then
    TIMESTAMP=$(date +%Y-%m-%dT%H-%M-%S)
    BACKUP_FILE="$BACKUP_DIR/pos_system_backup_$TIMESTAMP.db"
    cp "$DB_PATH" "$BACKUP_FILE"
    echo "✅ Database backed up to: $BACKUP_FILE"
    
    # Delete database
    rm "$DB_PATH"
    echo "✅ Database deleted. New database will be created on next app launch."
else
    echo "ℹ️  No database file found. New database will be created on next app launch."
fi
```

Make it executable and run:
```bash
chmod +x backup_and_clear_db.sh
./backup_and_clear_db.sh
```

## What Gets Backed Up

When using `CLEAR_DB=true`, the following is backed up:
- All users
- All products
- All orders (pending and synced)
- All stock information
- Device information

## Restoring from Backup

To restore a backup:

```bash
cd ~/Documents/pos_system/backups
cp pos_system_backup_YYYY-MM-DDTHH-MM-SS.db ~/Documents/pos_system.db
```

Or from Documents:
```bash
cd ~/Documents
cp pos_system_backup_YYYY-MM-DD_HH-MM-SS.db pos_system.db
```

## Complete Example: Launch with Clean DB

```bash
cd /Users/tommy/pos-system/frontend
flutter run -d macos --dart-define=ENV=uat --dart-define=DEVICE_ID=DFEA26CE-2FCD-4CD6-B62A-09476BDE938B --dart-define=CLEAR_DB=true
```

This will:
1. ✅ Backup existing database to `~/Documents/pos_system/backups/`
2. ✅ Delete the old database
3. ✅ Create a fresh database
4. ✅ Sync users and products from the UAT backend
5. ✅ Use device ID: `DFEA26CE-2FCD-4CD6-B62A-09476BDE938B`

## Finding Your Database

To find the exact location of your database:

```bash
# In Terminal, run:
ls -la ~/Documents/pos_system.db

# Or check if it exists:
if [ -f ~/Documents/pos_system.db ]; then
    echo "Database found at: ~/Documents/pos_system.db"
    ls -lh ~/Documents/pos_system.db
else
    echo "No database file found"
fi
```

## Troubleshooting

### Database file is locked

If you get an error that the database is locked:
1. Close the Flutter app completely
2. Wait a few seconds
3. Try again

### Backup failed

If backup fails, you can manually copy the file:
```bash
mkdir -p ~/Documents/pos_system/backups
cp ~/Documents/pos_system.db ~/Documents/pos_system/backups/pos_system_backup_manual.db
```

### Cannot find database

If the database doesn't exist, that's fine! The app will create a new one automatically.

### Permission denied

If you get permission errors:
```bash
chmod 644 ~/Documents/pos_system.db
```

## Notes

- Backups are stored with timestamps: `pos_system_backup_2026-02-03T10-30-45.db`
- The database is automatically recreated when the app starts
- Users and products will be synced from the backend after clearing
- Orders that haven't been synced will be lost (make sure to sync before clearing if needed)
- On macOS, the database path uses `~` (home directory) which expands to `/Users/<your-username>/`

