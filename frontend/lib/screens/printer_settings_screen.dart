import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart' as bt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../providers/notification_bar_provider.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart' as esc_pos_utils;
// Windows printer library (only available on Windows)
import 'package:windows_printer/windows_printer.dart' if (dart.library.html) 'package:windows_printer/windows_printer_stub.dart' as windows_printer;
import '../services/receipt_printer_helpers.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  String _printerType = 'network'; // 'network', 'bluetooth', or 'usb'
  String _printerIP = '';
  int _printerPort = 9100;
  String _usbSerialPort = '';
  String? _selectedUsbPrinterPath;
  String? _selectedUsbPrinterName;
  String? _selectedBluetoothAddress;
  String? _selectedBluetoothName;
  List<bt.BluetoothDevice> _bluetoothDevices = [];
  List<Map<String, String>> _usbPrinters = []; // {name: String, path: String}
  bool _isScanning = false;
  bool _isScanningUsb = false;
  bool _isTesting = false;
  String? _testMessage;
  
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _usbPortController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _scanBluetoothDevices();
    _scanUsbPrinters();
  }
  
  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _usbPortController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _printerType = prefs.getString('printer_type') ?? 'network';
      _printerIP = prefs.getString('printer_ip') ?? '';
      _printerPort = prefs.getInt('printer_port') ?? 9100;
      _usbSerialPort = prefs.getString('printer_usb_serial_port') ?? '';
      _selectedUsbPrinterPath = prefs.getString('printer_usb_serial_port');
      _selectedUsbPrinterName = prefs.getString('printer_usb_name');
      _selectedBluetoothAddress = prefs.getString('printer_bluetooth_address');
      _selectedBluetoothName = prefs.getString('printer_bluetooth_name');
      
      _ipController.text = _printerIP;
      _portController.text = _printerPort.toString();
      _usbPortController.text = _usbSerialPort;
    });
  }

  Future<void> _saveSettings() async {
    final l10n = AppLocalizations.of(context)!;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_type', _printerType);
    
    if (_printerType == 'network') {
      await prefs.setString('printer_ip', _ipController.text);
      await prefs.setInt('printer_port', int.tryParse(_portController.text) ?? 9100);
      await prefs.remove('printer_usb_serial_port');
      await prefs.remove('printer_bluetooth_address');
      await prefs.remove('printer_bluetooth_name');
    } else if (_printerType == 'usb') {
      if (_selectedUsbPrinterPath != null) {
        await prefs.setString('printer_usb_serial_port', _selectedUsbPrinterPath!);
        await prefs.setString('printer_usb_name', _selectedUsbPrinterName ?? '');
      }
      await prefs.remove('printer_ip');
      await prefs.remove('printer_port');
      await prefs.remove('printer_bluetooth_address');
      await prefs.remove('printer_bluetooth_name');
    } else {
      if (_selectedBluetoothAddress != null) {
        await prefs.setString('printer_bluetooth_address', _selectedBluetoothAddress!);
        await prefs.setString('printer_bluetooth_name', _selectedBluetoothName ?? '');
      }
      await prefs.remove('printer_ip');
      await prefs.remove('printer_port');
      await prefs.remove('printer_usb_serial_port');
    }
    
    if (mounted) {
      context.showNotification(l10n.settingsSavedSuccessfully, isSuccess: true);
    }
  }

  Future<void> _scanBluetoothDevices() async {
    setState(() {
      _isScanning = true;
      _bluetoothDevices = [];
    });

    try {
      // Get bonded devices (already paired)
      List<bt.BluetoothDevice> bondedDevices = await bt.FlutterBluetoothSerial.instance.getBondedDevices();
      
      // Also try to discover devices
      bt.FlutterBluetoothSerial.instance.startDiscovery().listen((result) {
        if (result.device != null && !_bluetoothDevices.contains(result.device!)) {
          setState(() {
            _bluetoothDevices.add(result.device!);
          });
        }
      });

      setState(() {
        _bluetoothDevices = bondedDevices;
        _isScanning = false;
      });
    } catch (e) {
      setState(() {
        _isScanning = false;
      });
      if (mounted) {
        context.showNotification('Error scanning Bluetooth: $e', isError: true);
      }
    }
  }

  Future<void> _listAllPrinters() async {
    setState(() {
      _isScanningUsb = true;
      _usbPrinters = [];
    });

    try {
      List<Map<String, String>> printers = [];

      // Windows printer detection
      if (Platform.isWindows) {
        try {
          // Try windows_printer library first (most reliable)
          try {
            final availablePrinters = await windows_printer.WindowsPrinter.getAvailablePrinters();
            debugPrint('windows_printer library found ${availablePrinters.length} printers');
            
            for (var printerName in availablePrinters) {
              printers.add({
                'name': printerName,
                'path': printerName,
                'port': '', // windows_printer handles ports internally
                'cups': 'false',
                'type': 'windows',
              });
              debugPrint('Found Windows printer (windows_printer): $printerName');
            }
            
            // If we got printers from the library, use them
            if (printers.isNotEmpty) {
              setState(() {
                _usbPrinters = printers;
                _isScanningUsb = false;
              });
              return;
            }
          } catch (e) {
            debugPrint('windows_printer library failed, falling back to PowerShell: $e');
          }
          
          // Fallback to PowerShell Get-Printer
          ProcessResult? result;
          try {
            // PowerShell command to get all printers with details
            result = await Process.run(
              'powershell',
              [
                '-Command',
                'Get-Printer | Select-Object Name, PortName, DriverName, PrinterStatus | ConvertTo-Json'
              ],
              runInShell: true,
            );
            debugPrint('PowerShell Get-Printer (JSON) succeeded');
          } catch (e) {
            debugPrint('PowerShell Get-Printer (JSON) failed: $e');
            // Fallback to wmic if PowerShell fails
            try {
              result = await Process.run(
                'wmic',
                ['printer', 'get', 'name,portname'],
                runInShell: true,
              );
              debugPrint('WMIC succeeded as fallback');
            } catch (e2) {
              debugPrint('Both PowerShell and WMIC failed: $e2');
            }
          }

          if (result != null && result.exitCode == 0) {
            final output = result.stdout.toString();
            
            // Try to parse JSON first (PowerShell output)
            if (output.trim().startsWith('[') || output.trim().startsWith('{')) {
              try {
                final jsonData = output.trim();
                // Handle both array and single object
                final jsonStr = jsonData.startsWith('[') ? jsonData : '[$jsonData]';
                final List<dynamic> printerList = json.decode(jsonStr) as List<dynamic>;
                
                for (var printer in printerList) {
                  final printerMap = printer as Map<String, dynamic>;
                  final printerName = printerMap['Name']?.toString() ?? '';
                  final portName = printerMap['PortName']?.toString() ?? '';
                  
                  if (printerName.isNotEmpty) {
                    printers.add({
                      'name': printerName,
                      'path': printerName,
                      'port': portName,
                      'cups': 'false',
                      'type': 'windows',
                    });
                    debugPrint('Found Windows printer (PowerShell): $printerName (Port: $portName)');
                  }
                }
              } catch (e) {
                debugPrint('Failed to parse PowerShell JSON: $e');
                // Fall through to text parsing
              }
            }
            
            // If JSON parsing failed or output is text format (wmic), parse as text
            if (printers.isEmpty) {
              final lines = output.split('\n');
              for (var line in lines) {
                final trimmed = line.trim();
                if (trimmed.isEmpty || trimmed.contains('Name') || trimmed.contains('PortName')) {
                  continue;
                }

                final parts = trimmed.split(RegExp(r'\s{2,}'));
                if (parts.isNotEmpty) {
                  final printerName = parts[0].trim();
                  final portName = parts.length > 1 ? parts[1].trim() : '';
                  
                  if (printerName.isNotEmpty && printerName != 'Name') {
                    printers.add({
                      'name': printerName,
                      'path': printerName,
                      'port': portName,
                      'cups': 'false',
                      'type': 'windows',
                    });
                    debugPrint('Found Windows printer (wmic): $printerName (Port: $portName)');
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Error listing Windows printers: $e');
        }
      } else {
        // macOS/Linux printer detection
        final env = Map<String, String>.from(Platform.environment);
        env['PATH'] = '/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin';

        // Try to get all printers using lpstat
        try {
          // Try lpstat -p first
          ProcessResult? result;
          try {
            result = await Process.run('/usr/bin/lpstat', ['-p'], environment: env);
          } catch (e) {
            debugPrint('lpstat -p failed: $e');
            // Try without -p flag
            try {
              result = await Process.run('/usr/bin/lpstat', [], environment: env);
            } catch (e2) {
              debugPrint('lpstat failed: $e2');
            }
          }

          if (result != null && result.exitCode == 0) {
            final lines = result.stdout.toString().split('\n');
            for (var line in lines) {
              String? printerName;
              
              if (line.startsWith('printer ')) {
                final parts = line.split(' ');
                if (parts.length >= 2) {
                  printerName = parts[1];
                }
              } else if (line.trim().isNotEmpty && 
                         !line.startsWith('system') && 
                         !line.startsWith('scheduler') &&
                         !line.startsWith('device for')) {
                // Try to extract printer name from other formats
                final nameMatch = RegExp(r'^(\S+)').firstMatch(line.trim());
                if (nameMatch != null) {
                  printerName = nameMatch.group(1);
                }
              }
              
              if (printerName != null && printerName.isNotEmpty) {
                // Add all printers, not just USB ones
                printers.add({
                  'name': printerName,
                  'path': printerName, // Use printer name as path for CUPS
                  'cups': 'true',
                });
              }
            }
          }
        } catch (e) {
          debugPrint('Error listing printers: $e');
        }
      }

      setState(() {
        _usbPrinters = printers;
        _isScanningUsb = false;
      });
    } catch (e) {
      setState(() {
        _isScanningUsb = false;
      });
      if (mounted) {
        context.showNotification('Error listing printers: $e', isError: true);
      }
    }
  }

  Future<void> _scanUsbPrinters() async {
    setState(() {
      _isScanningUsb = true;
      _usbPrinters = [];
    });

    try {
      List<Map<String, String>> printers = [];

      // Windows printer detection
      if (Platform.isWindows) {
        try {
          // Method 1: Try windows_printer library first (most reliable)
          try {
            final availablePrinters = await windows_printer.WindowsPrinter.getAvailablePrinters();
            debugPrint('windows_printer library found ${availablePrinters.length} printers');
            
            for (var printerName in availablePrinters) {
              printers.add({
                'name': printerName,
                'path': printerName,
                'port': '', // windows_printer handles ports internally
                'cups': 'false',
              });
              debugPrint('Found Windows printer (windows_printer): $printerName');
            }
            
            // If we got printers from the library, use them
            if (printers.isNotEmpty) {
              setState(() {
                _usbPrinters = printers;
                _isScanningUsb = false;
              });
              return;
            }
          } catch (e) {
            debugPrint('windows_printer library failed, falling back to PowerShell: $e');
          }
          
          // Method 2: Fallback to PowerShell Get-Printer
          ProcessResult? result;
          try {
            // Try PowerShell first (more reliable and available on all modern Windows)
            result = await Process.run(
              'powershell',
              ['-Command', 'Get-Printer | Select-Object Name,PortName | Format-Table -HideTableHeaders'],
              runInShell: true,
            );
            debugPrint('PowerShell Get-Printer succeeded');
          } catch (e) {
            debugPrint('PowerShell Get-Printer failed: $e');
            // Fallback to wmic if PowerShell fails
            try {
              result = await Process.run(
                'wmic',
                ['printer', 'get', 'name,portname'],
                runInShell: true,
              );
              debugPrint('WMIC succeeded as fallback');
            } catch (e2) {
              debugPrint('Both PowerShell and WMIC failed: $e2');
            }
          }

          if (result != null && result.exitCode == 0) {
            final lines = result.stdout.toString().split('\n');
            for (var line in lines) {
              final trimmed = line.trim();
              if (trimmed.isEmpty || trimmed.contains('Name') || trimmed.contains('PortName')) {
                continue;
              }

              // Parse printer name and port
              // Format can vary: "PrinterName  PortName" or just "PrinterName"
              final parts = trimmed.split(RegExp(r'\s{2,}'));
              if (parts.isNotEmpty) {
                final printerName = parts[0].trim();
                final portName = parts.length > 1 ? parts[1].trim() : '';
                
                if (printerName.isNotEmpty && printerName != 'Name') {
                  printers.add({
                    'name': printerName,
                    'path': printerName, // Use printer name for Windows
                    'port': portName,
                    'cups': 'false',
                  });
                  debugPrint('Found Windows printer: $printerName (Port: $portName)');
                }
              }
            }
          }

          // Method 2: Also check for COM ports (for direct serial/USB printers)
          try {
            // Try PowerShell first to list COM ports
            ProcessResult? comResult;
            try {
              comResult = await Process.run(
                'powershell',
                ['-Command', 'Get-WmiObject Win32_SerialPort | Select-Object DeviceID,Name | Format-Table -HideTableHeaders'],
                runInShell: true,
              );
              debugPrint('PowerShell Get-WmiObject Win32_SerialPort succeeded');
            } catch (e) {
              debugPrint('PowerShell Get-WmiObject failed: $e');
              // Fallback to wmic if PowerShell fails
              try {
                comResult = await Process.run(
                  'wmic',
                  ['path', 'win32_serialport', 'get', 'deviceid,name'],
                  runInShell: true,
                );
                debugPrint('WMIC succeeded as fallback for COM ports');
              } catch (e2) {
                debugPrint('Both PowerShell and WMIC failed for COM ports: $e2');
              }
            }
            
            if (comResult != null && comResult.exitCode == 0) {
              final comLines = comResult.stdout.toString().split('\n');
              for (var line in comLines) {
                final trimmed = line.trim();
                if (trimmed.isEmpty || trimmed.contains('DeviceID') || trimmed.contains('Name')) {
                  continue;
                }
                
                // Extract COM port (e.g., "COM3" from "COM3  USB Serial Port")
                final comMatch = RegExp(r'(COM\d+)', caseSensitive: false).firstMatch(trimmed);
                if (comMatch != null) {
                  final comPort = comMatch.group(1)!.toUpperCase();
                  // Extract name if available
                  final nameMatch = RegExp(r'COM\d+\s+(.+)').firstMatch(trimmed);
                  final portName = nameMatch?.group(1)?.trim() ?? comPort;
                  
                  printers.add({
                    'name': '$portName ($comPort)',
                    'path': comPort, // Use COM port as path for direct access
                    'port': comPort,
                    'cups': 'false',
                  });
                  debugPrint('Found COM port: $comPort ($portName)');
                }
              }
            }
          } catch (e) {
            debugPrint('Failed to list COM ports: $e');
          }
        } catch (e) {
          debugPrint('Error scanning Windows printers: $e');
        }
      } else {
        // macOS/Linux printer detection
        // Method 1: Get printers from CUPS (macOS Printers & Scanners)
        try {
        // Try using lpstat with full path and proper environment
        // On macOS, we need to set up the environment properly
        final env = Map<String, String>.from(Platform.environment);
        env['PATH'] = '/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin';
        
        // Get list of all printers - try different methods
        ProcessResult? result;
        
        // Method 1a: Try lpstat -p directly
        try {
          result = await Process.run('/usr/bin/lpstat', ['-p'], environment: env);
          debugPrint('lpstat -p exit code: ${result.exitCode}');
          debugPrint('lpstat -p stdout: ${result.stdout}');
          debugPrint('lpstat -p stderr: ${result.stderr}');
        } catch (e) {
          debugPrint('lpstat -p failed with exception: $e');
          // Try alternative method
        }
        
        // Method 1b: If lpstat fails, try lpstat without -p flag
        if (result == null || result.exitCode != 0) {
          try {
            result = await Process.run('/usr/bin/lpstat', [], environment: env);
            debugPrint('lpstat (no args) exit code: ${result.exitCode}');
            debugPrint('lpstat (no args) stdout: ${result.stdout}');
          } catch (e) {
            debugPrint('lpstat (no args) failed: $e');
          }
        }
        
        // Method 1c: Try using system_profiler to get USB printers
        if (result == null || result.exitCode != 0) {
          try {
            final systemProfilerResult = await Process.run('/usr/sbin/system_profiler', ['SPUSBDataType'], environment: env);
            if (systemProfilerResult.exitCode == 0) {
              debugPrint('system_profiler found USB devices');
              // Parse USB devices from system_profiler output
              final output = systemProfilerResult.stdout.toString();
              // Look for printer-related USB devices
              final printerMatches = RegExp(r'(\w+.*?Printer.*?|.*?Print.*?)', caseSensitive: false).allMatches(output);
              for (var match in printerMatches) {
                debugPrint('Found potential printer in USB: ${match.group(0)}');
              }
            }
          } catch (e) {
            debugPrint('system_profiler failed: $e');
          }
        }
        
        if (result != null && result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          debugPrint('Found ${lines.length} lines from lpstat');
          
          for (var line in lines) {
            String? printerName;
            
            if (line.startsWith('printer ')) {
              final parts = line.split(' ');
              if (parts.length >= 2) {
                printerName = parts[1];
              }
            } else if (line.trim().isNotEmpty && !line.startsWith('system') && !line.startsWith('scheduler')) {
              // Try to extract printer name from other formats
              final nameMatch = RegExp(r'(\S+)').firstMatch(line.trim());
              if (nameMatch != null) {
                printerName = nameMatch.group(1);
              }
            }
            
            if (printerName != null && printerName.isNotEmpty) {
              debugPrint('Processing printer: $printerName');
              
              // Get printer details including URI
              ProcessResult? deviceResult;
              try {
                deviceResult = await Process.run('/usr/bin/lpstat', ['-v', printerName], environment: env);
                debugPrint('lpstat -v $printerName exit code: ${deviceResult.exitCode}');
                debugPrint('lpstat -v $printerName output: ${deviceResult.stdout}');
              } catch (e) {
                debugPrint('lpstat -v $printerName failed: $e');
                // If we can't get details, still add the printer with just the name
                printers.add({
                  'name': printerName,
                  'path': printerName,
                  'uri': '',
                  'cups': 'true',
                  'type': 'unknown',
                });
                debugPrint('Added printer $printerName (details unavailable)');
                continue;
              }
              
              if (deviceResult != null && deviceResult.exitCode == 0) {
                final deviceOutput = deviceResult.stdout.toString();
                
                // Extract URI - try multiple patterns
                String? printerUri;
                final uriPatterns = [
                  RegExp(r'device for ([^:]+):\s*(.+)'),
                  RegExp(r'device for (.+?):\s*(.+)'),
                  RegExp(r'device:\s*(.+)'),
                ];
                
                for (var pattern in uriPatterns) {
                  final uriMatch = pattern.firstMatch(deviceOutput);
                  if (uriMatch != null) {
                    printerUri = uriMatch.groupCount >= 2 
                        ? uriMatch.group(2)?.trim() 
                        : uriMatch.group(1)?.trim();
                    break;
                  }
                }
                
                debugPrint('Printer URI for $printerName: $printerUri');
                
                // Show ALL printers (USB, local, and network)
                // Users can select any printer they want to use
                // Check if it's a USB printer or any local printer
                // USB printers can have: usb://, usb, or be local printers
                final isUsbPrinter = deviceOutput.contains('usb://') || 
                                    deviceOutput.contains('usb') ||
                                    (printerUri != null && printerUri.contains('usb'));
                
                // Also include all local printers (not network printers)
                final isLocalPrinter = printerUri != null && 
                                      !printerUri.startsWith('ipp://') &&
                                      !printerUri.startsWith('http://') &&
                                      !printerUri.startsWith('lpd://') &&
                                      !printerUri.startsWith('socket://');
                
                // Include network printers too (ipp://, http://, socket://, lpd://)
                final isNetworkPrinter = printerUri != null && 
                                        (printerUri.startsWith('ipp://') ||
                                         printerUri.startsWith('http://') ||
                                         printerUri.startsWith('lpd://') ||
                                         printerUri.startsWith('socket://'));
                
                // Show all printers - USB, local, and network
                if (isUsbPrinter || isLocalPrinter || isNetworkPrinter || printerUri == null) {
                  debugPrint('Adding printer $printerName (USB: $isUsbPrinter, Local: $isLocalPrinter, Network: $isNetworkPrinter)');
                  
                  // Try to find the raw device path
                  String? devicePath;
                  
                  // Method 1a: Check if URI contains device path
                  if (printerUri != null) {
                    final pathMatch = RegExp(r'(/dev/[^\s]+)').firstMatch(printerUri);
                    if (pathMatch != null) {
                      devicePath = pathMatch.group(1);
                      debugPrint('Found device path in URI: $devicePath');
                    }
                  }
                  
                  // Method 1b: Try to get device from lpoptions
                  if (devicePath == null) {
                    try {
                      final lpoptionsResult = await Process.run('/usr/bin/lpoptions', ['-p', printerName, '-l'], environment: env);
                      if (lpoptionsResult.exitCode == 0) {
                        final optionsOutput = lpoptionsResult.stdout.toString();
                        debugPrint('lpoptions output: $optionsOutput');
                        // Look for device path in options
                        final devMatch = RegExp(r'device.*?:\s*(/dev/[^\s]+)').firstMatch(optionsOutput);
                        if (devMatch != null) {
                          devicePath = devMatch.group(1);
                          debugPrint('Found device path in lpoptions: $devicePath');
                        }
                      }
                    } catch (e) {
                      debugPrint('Error getting lpoptions: $e');
                    }
                  }
                  
                  // Method 1c: Try to find device by scanning /dev for USB devices
                  if (devicePath == null) {
                    try {
                      final devDir = Directory('/dev');
                      if (await devDir.exists()) {
                        List<String> usbDevices = [];
                        await for (var entity in devDir.list()) {
                          if (entity is File) {
                            final path = entity.path;
                            // Check for USB serial ports
                            if (path.contains('usbserial') || 
                                path.contains('usbmodem') ||
                                (path.startsWith('/dev/tty.') && path.contains('USB')) ||
                                (path.startsWith('/dev/cu.') && path.contains('USB'))) {
                              usbDevices.add(path);
                            }
                          }
                        }
                        debugPrint('Found ${usbDevices.length} USB devices in /dev');
                        if (usbDevices.isNotEmpty) {
                          // Use the first USB device found
                          devicePath = usbDevices.first;
                          debugPrint('Using USB device: $devicePath');
                        }
                      }
                    } catch (e) {
                      debugPrint('Error scanning /dev: $e');
                    }
                  }
                  
                  // Add printer - use CUPS name if no device path found
                  printers.add({
                    'name': printerName,
                    'path': devicePath ?? printerName, // Use printer name as path for CUPS if no device
                    'uri': printerUri ?? '',
                    'cups': devicePath == null ? 'true' : 'false',
                    'type': isNetworkPrinter ? 'network' : (isUsbPrinter ? 'usb' : 'local'),
                  });
                  debugPrint('Added printer: $printerName with path: ${devicePath ?? printerName}');
                } else {
                  // Even if we can't determine the type, add it anyway
                  debugPrint('Adding printer $printerName (unknown type)');
                  printers.add({
                    'name': printerName,
                    'path': printerName,
                    'uri': printerUri ?? '',
                    'cups': 'true',
                    'type': 'unknown',
                  });
                }
              } else {
                debugPrint('Failed to get device info for $printerName: ${deviceResult.stderr}');
                // Still add the printer even if we can't get details
                printers.add({
                  'name': printerName,
                  'path': printerName,
                  'uri': '',
                  'cups': 'true',
                  'type': 'unknown',
                });
                debugPrint('Added printer $printerName (device info unavailable)');
              }
            }
          }
        } else {
          debugPrint('lpstat -p failed: ${result?.stderr}');
        }
        } catch (e, stackTrace) {
          debugPrint('Error getting CUPS printers: $e');
          debugPrint('Stack trace: $stackTrace');
        }

        // Method 2: Scan /dev directory for USB serial ports (fallback)
      if (printers.isEmpty) {
        try {
          final devDir = Directory('/dev');
          if (await devDir.exists()) {
            await for (var entity in devDir.list()) {
              if (entity is File) {
                final path = entity.path;
                // Check for common USB serial port patterns
                if (path.contains('usbserial') || 
                    path.contains('usbmodem') ||
                    (path.startsWith('/dev/tty.') && path.contains('USB')) ||
                    (path.startsWith('/dev/cu.') && path.contains('USB'))) {
                  // Check if this printer is already in the list
                  if (!printers.any((p) => p['path'] == path)) {
                    String name = path.split('/').last;
                    printers.add({
                      'name': name,
                      'path': path,
                    });
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Error scanning /dev directory: $e');
        }
      }
      } // Close else block for macOS/Linux

      setState(() {
        _usbPrinters = printers;
        _isScanningUsb = false;
      });
    } catch (e) {
      setState(() {
        _isScanningUsb = false;
      });
      if (mounted) {
        context.showNotification('Error scanning USB printers: $e', isError: true);
      }
    }
  }

  Future<void> _testPrinter() async {
    setState(() {
      _isTesting = true;
      _testMessage = null;
    });

    try {
      final profile = await esc_pos_utils.CapabilityProfile.load();
      final generator = esc_pos_utils.Generator(esc_pos_utils.PaperSize.mm80, profile);
      
      List<int> bytes = [];
      bytes += generator.reset();
      bytes += generator.text(
        'Printer Test',
        styles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center, bold: true, height: esc_pos_utils.PosTextSize.size2),
      );
      bytes += generator.feed(1);
      bytes += generator.text(
        'If you can read this,',
        styles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center),
      );
      bytes += generator.text(
        'your printer is working!',
        styles: esc_pos_utils.PosStyles(align: esc_pos_utils.PosAlign.center),
      );
      bytes += generator.feed(2);
      bytes += generator.cut();

      if (_printerType == 'bluetooth') {
        // Note: esc_pos_printer doesn't support Bluetooth directly
        // For now, throw an error
        throw Exception('Bluetooth printing not yet supported. Please use network or USB printing.');
      } else if (_printerType == 'usb') {
        // USB printer via serial port or CUPS (macOS) or Windows printer
        if (_selectedUsbPrinterPath == null || _selectedUsbPrinterPath!.isEmpty) {
          throw Exception('Please select a USB printer');
        }
        
        if (Platform.isWindows) {
          // Windows USB printing - use the helper function
          await ReceiptPrinterHelpers.sendToPrinter(
            bytes,
            {
              'type': 'usb',
              'usb_serial_port': _selectedUsbPrinterPath,
            },
          );
        } else {
          // macOS/Linux USB printing
          // Check if this is a CUPS printer name (doesn't start with /dev/)
          final isCupsPrinter = !_selectedUsbPrinterPath!.startsWith('/dev/');
          
          if (isCupsPrinter) {
            // Use CUPS lp command to print raw data
            final env = Map<String, String>.from(Platform.environment);
            env['PATH'] = '/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin';
            
            // Try to pipe data directly to lp via stdin
            // This avoids file permission issues
            ProcessResult? result;
            String? errorMsg;
            
            try {
              // Try with temp file first (more reliable with sandbox)
              final tempDir = await getTemporaryDirectory();
              final tempFile = File('${tempDir.path}/escpos_test_${DateTime.now().millisecondsSinceEpoch}.raw');
              try {
                await tempFile.writeAsBytes(bytes);
                
                // Verify file was written
                if (!await tempFile.exists()) {
                  throw Exception('Failed to create temporary file');
                }
                
                // Try using shell to execute lp (may help with sandbox)
                final printerName = _selectedUsbPrinterPath!.trim();
                final filePath = tempFile.path;
                
                // Ensure file path is properly encoded and doesn't contain special characters
                // Escape any special characters in the file path
                final escapedFilePath = filePath.replaceAll("'", "'\\''");
                final escapedPrinterName = printerName.replaceAll("'", "'\\''");
                
                // Use shell to execute lp command with proper escaping
                result = await Process.run(
                  '/bin/sh',
                  [
                    '-c',
                    "/usr/bin/lp -d '$escapedPrinterName' -o raw '$escapedFilePath'",
                  ],
                  environment: env,
                  runInShell: false,
                );
                
                if (result.exitCode != 0) {
                  final stderrMsg = result.stderr.toString();
                  final stdoutMsg = result.stdout.toString();
                  errorMsg = stderrMsg.isNotEmpty ? stderrMsg : stdoutMsg;
                }
              } finally {
                if (await tempFile.exists()) {
                  await tempFile.delete();
                }
              }
            } catch (e) {
              errorMsg = e.toString();
              debugPrint('lp command via shell failed: $e');
              
              // Fallback: try direct Process.start with stdin
              try {
                final process = await Process.start('/usr/bin/lp', [
                  '-d', _selectedUsbPrinterPath!.trim(),
                  '-o', 'raw',
                ], environment: env, mode: ProcessStartMode.normal);
                
                // Read stderr in parallel
                final stderrFuture = process.stderr.toList();
                
                // Write bytes to stdin
                process.stdin.add(bytes);
                await process.stdin.close();
                
                // Wait for process to complete
                final exitCode = await process.exitCode;
                final stderr = await stderrFuture;
                final stderrStr = String.fromCharCodes(stderr.expand((list) => list));
                
                result = ProcessResult(
                  process.pid,
                  exitCode,
                  '',
                  stderrStr,
                );
                
                if (exitCode != 0) {
                  errorMsg = stderrStr;
                }
              } catch (e2) {
                debugPrint('lp with stdin also failed: $e2');
                errorMsg = e2.toString();
              }
            }

            if (result == null || result.exitCode != 0) {
              final stderrMsg = errorMsg ?? result?.stderr.toString() ?? '';
              final stdoutMsg = result?.stdout.toString() ?? '';
              final finalErrorMsg = stderrMsg.isNotEmpty ? stderrMsg : stdoutMsg;
              
              debugPrint('lp command failed with exit code ${result?.exitCode ?? -1}');
              debugPrint('stderr: $stderrMsg');
              debugPrint('stdout: $stdoutMsg');
              
              // Check for common error messages
              if (finalErrorMsg.contains('does not exist') || 
                  finalErrorMsg.contains('not found') ||
                  finalErrorMsg.contains('unknown destination')) {
                throw Exception('Printer "${_selectedUsbPrinterPath}" not found. Please check the exact printer name in macOS Printers & Scanners. The name must match exactly (case-sensitive).');
              }
              throw Exception('Print failed: $finalErrorMsg');
            }
          } else {
            // Direct device access (macOS/Linux serial port)
            final file = File(_selectedUsbPrinterPath!);
            if (!await file.exists()) {
              throw Exception('USB serial port not found: $_selectedUsbPrinterPath');
            }
            
            final raf = await file.open(mode: FileMode.write);
            try {
              await raf.writeFrom(bytes);
              await raf.flush();
            } finally {
              await raf.close();
            }
          }
        }
      } else {
        // Network printer
        if (_ipController.text.isEmpty) {
          throw Exception('Please enter printer IP address');
        }
        
        // Send to network printer via raw socket
        final socket = await Socket.connect(_ipController.text, int.tryParse(_portController.text) ?? 9100);
        try {
          socket.add(bytes);
          await socket.flush();
        } finally {
          await socket.close();
        }
      }

      // Add a small delay to ensure print job is sent
      await Future.delayed(const Duration(milliseconds: 500));
      
      setState(() {
        _isTesting = false;
        _testMessage = 'Test print sent! Check your printer. If nothing prints, verify the printer is connected and the name matches exactly.';
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
        _testMessage = 'Test failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.printerSettings),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Printer Type Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.connectionType,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    RadioListTile<String>(
                      title: Text(l10n.network),
                      value: 'network',
                      groupValue: _printerType,
                      onChanged: (value) {
                        setState(() {
                          _printerType = value!;
                        });
                      },
                    ),
                    RadioListTile<String>(
                      title: Text(l10n.bluetooth),
                      value: 'bluetooth',
                      groupValue: _printerType,
                      onChanged: (value) {
                        setState(() {
                          _printerType = value!;
                        });
                      },
                    ),
                    RadioListTile<String>(
                      title: Text(l10n.usb),
                      value: 'usb',
                      groupValue: _printerType,
                      onChanged: (value) {
                        setState(() {
                          _printerType = value!;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Network Settings
            if (_printerType == 'network') ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.networkSettings,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _ipController,
                        decoration: InputDecoration(
                          labelText: l10n.printerIPAddress,
                          hintText: '192.168.1.100',
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          setState(() {
                            _printerIP = value;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _portController,
                        decoration: InputDecoration(
                          labelText: l10n.printerPort,
                          hintText: '9100',
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          setState(() {
                            _printerPort = int.tryParse(value) ?? 9100;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
            
            // USB Settings
            if (_printerType == 'usb') ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            l10n.usbSettings,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: _isScanningUsb
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.list),
                                onPressed: _isScanningUsb ? null : _listAllPrinters,
                                tooltip: 'List all printers (quick scan)',
                              ),
                              IconButton(
                                icon: _isScanningUsb
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.refresh),
                                onPressed: _isScanningUsb ? null : _scanUsbPrinters,
                                tooltip: 'Scan for all printers (detailed scan)',
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_usbPrinters.isEmpty && !_isScanningUsb) ...[
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('No printers found'),
                              const SizedBox(height: 8),
                              Text(
                                'Try clicking the refresh button above to scan for printers, or manually enter your printer name from macOS Printers & Scanners:',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _usbPortController,
                                decoration: InputDecoration(
                                  labelText: 'Printer Name',
                                  hintText: 'Enter printer name from Printers & Scanners',
                                  border: const OutlineInputBorder(),
                                  helperText: 'Tip: The name must match exactly as shown in Printers & Scanners',
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _usbSerialPort = value;
                                    _usbPortController.text = value;
                                    if (value.isNotEmpty) {
                                      _selectedUsbPrinterPath = value;
                                      _selectedUsbPrinterName = value;
                                    } else {
                                      _selectedUsbPrinterPath = null;
                                      _selectedUsbPrinterName = null;
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                icon: const Icon(Icons.info_outline, size: 16),
                                label: const Text('How to find the exact printer name'),
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Finding Printer Name'),
                                      content: const Text(
                                        'To find the exact printer name:\n\n'
                                        '1. Open Terminal\n'
                                        '2. Run: lpstat -p\n'
                                        '3. Look for a line starting with "printer"\n'
                                        '4. The name after "printer" is the exact name to use\n\n'
                                        'Example: "printer Printer_POS-80" means use "Printer_POS-80"',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          child: const Text('OK'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ]
                      else if (_isScanningUsb)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        ..._usbPrinters.map((printer) {
                          final isSelected = _selectedUsbPrinterPath == printer['path'];
                          final printerType = printer['type'] ?? 'unknown';
                          final typeLabel = printerType == 'network' ? 'Network' : 
                                          printerType == 'usb' ? 'USB' : 
                                          printerType == 'local' ? 'Local' : '';
                          return ListTile(
                            title: Text(printer['name'] ?? 'Unknown Printer'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(printer['path'] ?? ''),
                                if (typeLabel.isNotEmpty)
                                  Text(
                                    typeLabel,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
                                    ),
                                  ),
                              ],
                            ),
                            leading: Icon(
                              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: isSelected ? Theme.of(context).primaryColor : null,
                            ),
                            onTap: () {
                              setState(() {
                                _selectedUsbPrinterPath = printer['path'];
                                _selectedUsbPrinterName = printer['name'];
                                _usbPortController.text = printer['path'] ?? '';
                              });
                            },
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ],

            // Bluetooth Settings
            if (_printerType == 'bluetooth') ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            l10n.bluetoothSettings,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          IconButton(
                            icon: _isScanning
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh),
                            onPressed: _isScanning ? null : _scanBluetoothDevices,
                            tooltip: 'Scan for devices',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_bluetoothDevices.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(l10n.noBluetoothDevicesFound),
                        )
                      else
                        ..._bluetoothDevices.map((device) {
                          final isSelected = _selectedBluetoothAddress == device.address;
                          return ListTile(
                            title: Text(device.name ?? 'Unknown Device'),
                            subtitle: Text(device.address),
                            leading: Icon(
                              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: isSelected ? Theme.of(context).primaryColor : null,
                            ),
                            onTap: () {
                              setState(() {
                                _selectedBluetoothAddress = device.address;
                                _selectedBluetoothName = device.name;
                              });
                            },
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Test Button
            if (_testMessage != null)
              Card(
                color: _testMessage!.contains('successful')
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _testMessage!,
                    style: TextStyle(
                      color: _testMessage!.contains('successful')
                          ? Colors.green.shade900
                          : Colors.red.shade900,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Test Printer Button
            ElevatedButton.icon(
              onPressed: _isTesting ? null : _testPrinter,
              icon: _isTesting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print),
              label: Text(_isTesting ? l10n.scanning : l10n.testPrinter),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),

            const SizedBox(height: 16),

            // Save Button
            ElevatedButton(
              onPressed: _saveSettings,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white, // Explicit white text color
              ),
              child: Text(
                l10n.saveSettings,
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


