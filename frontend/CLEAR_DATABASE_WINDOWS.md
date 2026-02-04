# Clearing Database on Windows

This guide explains how to backup and clear the local SQLite database when launching the Flutter app.

## Database Location

The database is stored at:
```
C:\Users\<YourUsername>\Documents\pos_system.db
```

Backups are stored at:
```
C:\Users\<YourUsername>\Documents\pos_system\backups\
```

## Method 1: Launch with Clean Database (Recommended)

This will automatically backup the existing database and create a fresh one:

```cmd
cd frontend
flutter run -d windows --dart-define=ENV=uat --dart-define=DEVICE_ID=DFEA26CE-2FCD-4CD6-B62A-09476BDE938B --dart-define=CLEAR_DB=true
```

Or for a built executable, you can set the environment variable:
```cmd
set CLEAR_DB=true
flutter run -d windows --dart-define=ENV=uat --dart-define=DEVICE_ID=DFEA26CE-2FCD-4CD6-B62A-09476BDE938B
```

## Method 2: Manual Backup and Delete

### Step 1: Backup the Database

The database is automatically backed up when you use `CLEAR_DB=true`, but you can also manually backup:

1. Navigate to the database location:
   ```cmd
   cd %USERPROFILE%\Documents
   ```

2. Copy the database file:
   ```cmd
   copy pos_system.db pos_system_backup_manual.db
   ```

Or create a timestamped backup:
```cmd
copy pos_system.db pos_system_backup_%date:~-4,4%%date:~-10,2%%date:~-7,2%_%time:~0,2%%time:~3,2%%time:~6,2%.db
```

### Step 2: Delete the Database

```cmd
del %USERPROFILE%\Documents\pos_system.db
```

The app will automatically create a new database when it starts.

## Method 3: Using PowerShell

```powershell
# Backup
$backupPath = "$env:USERPROFILE\Documents\pos_system_backup_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').db"
Copy-Item "$env:USERPROFILE\Documents\pos_system.db" $backupPath
Write-Host "Database backed up to: $backupPath"

# Delete
Remove-Item "$env:USERPROFILE\Documents\pos_system.db" -ErrorAction SilentlyContinue
Write-Host "Database deleted. New database will be created on next app launch."
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

```cmd
cd %USERPROFILE%\Documents
copy pos_system_backup_YYYY-MM-DD_HH-MM-SS.db pos_system.db
```

Or from the backups folder:
```cmd
cd %USERPROFILE%\Documents\pos_system\backups
copy pos_system_backup_YYYY-MM-DDTHH-MM-SS.db %USERPROFILE%\Documents\pos_system.db
```

## Complete Example: Launch with Clean DB

```cmd
cd C:\path\to\pos-system\frontend
flutter run -d windows --dart-define=ENV=uat --dart-define=DEVICE_ID=DFEA26CE-2FCD-4CD6-B62A-09476BDE938B --dart-define=CLEAR_DB=true
```

This will:
1. ✅ Backup existing database to `Documents\pos_system\backups\`
2. ✅ Delete the old database
3. ✅ Create a fresh database
4. ✅ Sync users and products from the UAT backend
5. ✅ Use device ID: `DFEA26CE-2FCD-4CD6-B62A-09476BDE938B`

## Troubleshooting

### Database file is locked

If you get an error that the database is locked:
1. Close the Flutter app completely
2. Wait a few seconds
3. Try again

### Backup failed

If backup fails, you can manually copy the file:
```cmd
cd %USERPROFILE%\Documents
if exist pos_system.db (
    mkdir pos_system\backups 2>nul
    copy pos_system.db pos_system\backups\pos_system_backup_manual.db
)
```

### Cannot find database

If the database doesn't exist, that's fine! The app will create a new one automatically.

## Notes

- Backups are stored with timestamps: `pos_system_backup_2026-02-03T10-30-45.db`
- The database is automatically recreated when the app starts
- Users and products will be synced from the backend after clearing
- Orders that haven't been synced will be lost (make sure to sync before clearing if needed)

