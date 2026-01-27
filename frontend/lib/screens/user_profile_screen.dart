import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:pos_system/l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../providers/auth_provider.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _currentPinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  Map<String, dynamic>? _user;
  bool _loading = true;
  bool _saving = false;
  XFile? _selectedImage;
  String? _uploadedIconUrl; // Store the uploaded icon URL from server
  Color _bgColor = const Color(0xFF1976D2);
  Color _textColor = Colors.white;
  String _iconMode = 'color'; // 'color' or 'upload'
  bool _iconDialogOpen = false;
  int _iconRefreshKey = 0; // Key to force icon refresh

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _currentPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    try {
      setState(() => _loading = true);
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      if (userId != null) {
        final userData = await ApiService.instance.getUser(userId);
        setState(() {
          _user = userData;
          // Pre-select saved colors if available
          if (userData['icon_bg_color'] != null && userData['icon_bg_color'].toString().isNotEmpty) {
            try {
              _bgColor = _parseColor(userData['icon_bg_color'].toString());
            } catch (e) {
              _bgColor = const Color(0xFF1976D2); // Default blue
            }
          }
          if (userData['icon_text_color'] != null && userData['icon_text_color'].toString().isNotEmpty) {
            try {
              _textColor = _parseColor(userData['icon_text_color'].toString());
            } catch (e) {
              _textColor = Colors.white; // Default white
            }
          }
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      print('Error loading user: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _updatePIN() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_newPinController.text != _confirmPinController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.pinMismatch ?? 'PINs do not match')),
      );
      return;
    }

    try {
      setState(() => _saving = true);
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      if (userId != null) {
        await ApiService.instance.updateUserPIN(
          userId,
          _currentPinController.text,
          _newPinController.text,
        );
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.pinUpdated ?? 'PIN updated successfully')),
      );
      _currentPinController.clear();
      _newPinController.clear();
      _confirmPinController.clear();
      await _loadUser();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _updateIcon() async {
    try {
      setState(() => _saving = true);
      Map<String, dynamic>? responseData;
      if (_iconMode == 'upload' && _selectedImage != null) {
        responseData = await ApiService.instance.updateUserIconFile(_user!['id'], _selectedImage!);
      } else if (_iconMode == 'color') {
        // Convert Color to hex string
        String bgColorHex = '#${_bgColor.value.toRadixString(16).substring(2)}';
        String textColorHex = '#${_textColor.value.toRadixString(16).substring(2)}';
        responseData = await ApiService.instance.updateUserIconColors(_user!['id'], bgColorHex, textColorHex);
      }
      
      // Get the updated icon_url from the response
      String? updatedIconUrl;
      if (responseData != null && responseData['icon_url'] != null) {
        updatedIconUrl = responseData['icon_url'].toString();
        print('Icon updated - new icon_url from response: $updatedIconUrl');
      } else {
        // Fallback: Reload user data to get updated icon_url from server
        print('Icon updated - reloading user from server...');
        await _loadUser();
        updatedIconUrl = _user!['icon_url']?.toString();
        print('Icon updated - icon_url from reloaded user: $updatedIconUrl');
      }
      
      // Store the uploaded icon URL for preview
      if (updatedIconUrl != null && updatedIconUrl.isNotEmpty) {
        setState(() {
          _uploadedIconUrl = updatedIconUrl;
        });
      }
      
      // Update local database with new icon_url
      if (updatedIconUrl != null && updatedIconUrl.isNotEmpty) {
        print('Updating local database with icon_url: $updatedIconUrl');
        await DatabaseService.instance.updateUserIcon(_user!['id'], updatedIconUrl);
        // Also update the local _user map and force widget rebuild
        setState(() {
          _user = Map<String, dynamic>.from(_user!);
          _user!['icon_url'] = updatedIconUrl;
        });
        print('Local database and state updated successfully');
      } else {
        print('Warning: updatedIconUrl is null or empty');
      }
      
      // Sync all users from server to update the user list with new icon
      await _syncUsersFromServer();
      
      // Reload user to ensure we have the latest data
      await _loadUser();
      
      // Force icon refresh by updating the key
      setState(() {
        _iconRefreshKey++;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.iconUpdated ?? 'Icon updated successfully')),
      );
      // Keep dialog open to show the updated icon from server
      setState(() {
        _selectedImage = null; // Clear local file selection so server version shows
      });
    } catch (e) {
      print('Error updating icon: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _syncUsersFromServer() async {
    try {
      final deviceCode = ApiService.instance.deviceCode;
      if (deviceCode == null) {
        print('Device code not available, skipping user sync');
        return;
      }
      
      print('Syncing users from server after icon update...');
      // Fetch users from API
      final users = await ApiService.instance.getUsersForDevice(deviceCode);
      
      // Save to local database (this will update all users including the one with new icon)
      if (users.isNotEmpty) {
        await DatabaseService.instance.saveUsers(
          users.cast<Map<String, dynamic>>(),
        );
        print('Users synced successfully after icon update');
      }
    } catch (e) {
      print('Error syncing users after icon update: $e');
      // Don't show error to user, just log it
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = image;
        _iconMode = 'upload';
      });
      print('Image selected: ${image.path}'); // Debug
    }
  }

  String _getInitials() {
    if (_user == null) return '?';
    final firstName = _user!['first_name'] ?? '';
    final lastName = _user!['last_name'] ?? '';
    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '${firstName[0]}${lastName[0]}'.toUpperCase();
    }
    return _user!['username']?[0]?.toUpperCase() ?? '?';
  }

  Widget _buildUserIcon() {
    final iconUrl = _user!['icon_url']?.toString();
    if (iconUrl != null && iconUrl.isNotEmpty) {
      // Check if it's a data URI
      if (iconUrl.startsWith('data:image')) {
        final svgWidget = _buildDataUriImage(iconUrl, 50);
        if (svgWidget != null) {
          // SVG image - ensure it's circular and centered
          return KeyedSubtree(
            key: ValueKey('user_icon_${_user!['id']}_${iconUrl}_$_iconRefreshKey'),
            child: ClipOval(
              child: Container(
                width: 100,
                height: 100,
                color: Theme.of(context).primaryColor,
                child: svgWidget,
              ),
            ),
          );
        } else {
          // PNG/JPEG data URI
          try {
            final commaIndex = iconUrl.indexOf(',');
            if (commaIndex != -1) {
              final base64Data = iconUrl.substring(commaIndex + 1);
              final bytes = base64Decode(base64Data);
              return KeyedSubtree(
                key: ValueKey('user_icon_${_user!['id']}_${iconUrl}_$_iconRefreshKey'),
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: Theme.of(context).primaryColor,
                  backgroundImage: MemoryImage(bytes),
                ),
              );
            }
          } catch (e) {
            print('Error loading data URI image: $e');
          }
        }
      } else {
        // Regular network URL - use KeyedSubtree to force rebuild when icon_url changes
        // Add cache buster only when icon is refreshed
        final cacheBusterUrl = _iconRefreshKey > 0 && iconUrl.contains('?')
            ? '$iconUrl&_t=$_iconRefreshKey'
            : _iconRefreshKey > 0 && !iconUrl.contains('?')
                ? '$iconUrl?_t=$_iconRefreshKey'
                : iconUrl;
        return KeyedSubtree(
          key: ValueKey('user_icon_${_user!['id']}_${iconUrl}_$_iconRefreshKey'),
          child: CircleAvatar(
            radius: 50,
            backgroundColor: Theme.of(context).primaryColor,
            backgroundImage: CachedNetworkImageProvider(cacheBusterUrl),
            child: iconUrl.isEmpty ? Text(
              _getInitials(),
              style: const TextStyle(
                fontSize: 40,
                fontFamily: 'monospace', // Match backend basicfont.Face7x13
                fontWeight: FontWeight.normal,
                color: Colors.white,
              ),
            ) : null,
          ),
        );
      }
    }
    // Fallback to initials
    return CircleAvatar(
      radius: 50,
      backgroundColor: Theme.of(context).primaryColor,
      child: Text(
        _getInitials(),
        style: const TextStyle(fontSize: 40, color: Colors.white),
      ),
    );
  }

  Widget? _buildDataUriImage(String dataUri, double size) {
    try {
      // Parse data URI: data:image/svg+xml;base64,<base64data>
      if (dataUri.startsWith('data:image')) {
        final commaIndex = dataUri.indexOf(',');
        if (commaIndex == -1) return null;

        final base64Data = dataUri.substring(commaIndex + 1);
        final bytes = base64Decode(base64Data);

        // For SVG, use flutter_svg to render
        if (dataUri.contains('svg')) {
          final svgString = utf8.decode(bytes);
          // Ensure SVG has viewBox for proper centering
          String processedSvg = svgString;
          if (!svgString.contains('viewBox')) {
            // Add viewBox if missing
            processedSvg = svgString.replaceFirst(
              '<svg',
              '<svg viewBox="0 0 100 100" preserveAspectRatio="xMidYMid meet"',
            );
          }
          return SvgPicture.string(
            processedSvg,
            width: size * 2,
            height: size * 2,
            fit: BoxFit.fill,
            alignment: Alignment.center,
          );
        }
        // For PNG/JPEG, return null to use MemoryImage in CircleAvatar
        return null;
      }
    } catch (e) {
      print('Error loading data URI image: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.profile ?? 'Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.profile ?? 'Profile')),
        body: const Center(child: Text('Failed to load user data')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profile ?? 'Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Information
            Paper(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.userInfo ?? 'User Information',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow(l10n.username ?? 'Username', _user!['username'] ?? ''),
                    _buildInfoRow(l10n.firstName ?? 'First Name', _user!['first_name'] ?? ''),
                    _buildInfoRow(l10n.lastName ?? 'Last Name', _user!['last_name'] ?? ''),
                    _buildInfoRow(l10n.email ?? 'Email', _user!['email'] ?? ''),
                    _buildInfoRow(l10n.role ?? 'Role', _user!['role'] ?? ''),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Profile Icon
            Paper(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.profileIcon ?? 'Profile Icon',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Stack(
                        children: [
                          _buildUserIcon(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _selectedImage = null; // Reset selected image
                          
                          // Ensure colors are loaded from user data
                          if (_user!['icon_bg_color'] != null && _user!['icon_bg_color'].toString().isNotEmpty) {
                            try {
                              _bgColor = _parseColor(_user!['icon_bg_color'].toString());
                            } catch (e) {
                              _bgColor = const Color(0xFF1976D2);
                            }
                          }
                          if (_user!['icon_text_color'] != null && _user!['icon_text_color'].toString().isNotEmpty) {
                            try {
                              _textColor = _parseColor(_user!['icon_text_color'].toString());
                            } catch (e) {
                              _textColor = Colors.white;
                            }
                          }
                          
                          // Check if user has an icon from server
                          final iconUrl = _user!['icon_url']?.toString();
                          if (iconUrl != null && iconUrl.isNotEmpty && !iconUrl.startsWith('data:image')) {
                            // User has an uploaded image (not a generated data URI)
                            _iconMode = 'upload';
                            _uploadedIconUrl = iconUrl; // Set to current server icon
                          } else {
                            // No uploaded image, use color mode
                            _iconMode = 'color';
                            _uploadedIconUrl = null;
                          }
                          
                          _showIconDialog(context);
                        },
                        icon: const Icon(Icons.edit),
                        label: Text(l10n.changeIcon ?? 'Change Icon'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Change PIN
            Paper(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.changePIN ?? 'Change PIN',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.pinInfo ?? 'Enter your current PIN and a new PIN to change it.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _currentPinController,
                        decoration: InputDecoration(
                          labelText: l10n.currentPIN ?? 'Current PIN',
                          border: const OutlineInputBorder(),
                        ),
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l10n.currentPINRequired;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _newPinController,
                        decoration: InputDecoration(
                          labelText: l10n.newPIN ?? 'New PIN',
                          border: const OutlineInputBorder(),
                        ),
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l10n.newPINRequired;
                          }
                          if (value.length < 4) {
                            return l10n.pinMinLength ?? 'PIN must be at least 4 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmPinController,
                        decoration: InputDecoration(
                          labelText: l10n.confirmPIN ?? 'Confirm New PIN',
                          border: const OutlineInputBorder(),
                        ),
                        obscureText: true,
                        validator: (value) {
                          if (value != _newPinController.text) {
                            return l10n.pinMismatch ?? 'PINs do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _updatePIN,
                          child: _saving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(l10n.updatePIN ?? 'Update PIN'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showIconDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.9,
            builder: (context, scrollController) {
              final l10n = AppLocalizations.of(context)!;
              return Material(
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                elevation: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    color: Theme.of(context).cardColor,
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                l10n.changeIcon ?? 'Change Icon',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _iconMode = 'color';
                                      _selectedImage = null;
                                    });
                                    setModalState(() {}); // Update modal state
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _iconMode == 'color' ? Theme.of(context).primaryColor : null,
                                    foregroundColor: _iconMode == 'color' ? Colors.white : null,
                                  ),
                                  child: Text(l10n.generateFromColors ?? 'Generate from Colors'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _iconMode = 'upload';
                                    });
                                    setModalState(() {}); // Update modal state
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _iconMode == 'upload' ? Theme.of(context).primaryColor : null,
                                    foregroundColor: _iconMode == 'upload' ? Colors.white : null,
                                  ),
                                  child: Text(l10n.uploadImage ?? 'Upload Image'),
                                ),
                              ),
                            ],
                          ),
                      const SizedBox(height: 16),
                      Center(
                        child: Builder(
                          builder: (context) {
                            if (_iconMode == 'upload') {
                              if (_selectedImage != null) {
                                return ClipOval(
                                  child: Image.file(
                                    File(_selectedImage!.path),
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return CircleAvatar(
                                        radius: 50,
                                        backgroundColor: Theme.of(context).primaryColor,
                                        child: const Icon(Icons.error, color: Colors.white),
                                      );
                                    },
                                  ),
                                );
                              }
                              
                              String? iconUrlToShow = _uploadedIconUrl;
                              if (iconUrlToShow == null || iconUrlToShow.isEmpty) {
                                iconUrlToShow = _user!['icon_url']?.toString();
                              }
                              
                              if (iconUrlToShow != null && iconUrlToShow.isNotEmpty) {
                                if (iconUrlToShow.startsWith('data:image')) {
                                  final svgWidget = _buildDataUriImage(iconUrlToShow, 50);
                                  if (svgWidget != null) {
                                    return ClipOval(
                                      child: Container(
                                        width: 100,
                                        height: 100,
                                        color: Theme.of(context).primaryColor,
                                        child: svgWidget,
                                      ),
                                    );
                                  } else {
                                    try {
                                      final commaIndex = iconUrlToShow.indexOf(',');
                                      if (commaIndex != -1) {
                                        final base64Data = iconUrlToShow.substring(commaIndex + 1);
                                        final bytes = base64Decode(base64Data);
                                        return CircleAvatar(
                                          radius: 50,
                                          backgroundColor: Theme.of(context).primaryColor,
                                          backgroundImage: MemoryImage(bytes),
                                        );
                                      }
                                    } catch (e) {
                                      print('Error loading uploaded data URI: $e');
                                    }
                                  }
                                } else {
                                  return CircleAvatar(
                                    radius: 50,
                                    backgroundColor: Theme.of(context).primaryColor,
                                    backgroundImage: CachedNetworkImageProvider(iconUrlToShow),
                                    onBackgroundImageError: (exception, stackTrace) {
                                      print('Error loading network image: $exception');
                                    },
                                  );
                                }
                              }
                            }
                            
                            return CircleAvatar(
                              radius: 50,
                              backgroundColor: _iconMode == 'color' ? _bgColor : Theme.of(context).primaryColor,
                              child: Text(
                                _getInitials(),
                                style: TextStyle(
                                  fontSize: 40,
                                  fontFamily: 'monospace', // Match backend basicfont.Face7x13
                                  fontWeight: FontWeight.normal,
                                  color: _iconMode == 'color' ? _textColor : Colors.white,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_iconMode == 'color') ...[
                        ListTile(
                          title: Text(l10n.backgroundColor ?? 'Background Color'),
                          trailing: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: _bgColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey, width: 2),
                            ),
                          ),
                          onTap: () => _showColorPicker(context, true, setModalState),
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          title: Text(l10n.textColor ?? 'Text Color'),
                          trailing: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: _textColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey, width: 2),
                            ),
                          ),
                          onTap: () => _showColorPicker(context, false, setModalState),
                        ),
                      ] else ...[
                        ElevatedButton.icon(
                          onPressed: () async {
                            final picker = ImagePicker();
                            final image = await picker.pickImage(source: ImageSource.gallery);
                            if (image != null) {
                              setState(() {
                                _selectedImage = image;
                                _iconMode = 'upload';
                              });
                              setModalState(() {}); // Update modal state
                            }
                          },
                          icon: const Icon(Icons.upload),
                          label: Text(l10n.selectImage ?? 'Select Image'),
                        ),
                        if (_selectedImage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(_selectedImage!.name),
                          ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(l10n.cancel ?? 'Cancel'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _saving || (_iconMode == 'upload' && _selectedImage == null && _uploadedIconUrl == null)
                                  ? null
                                  : () async {
                                      await _updateIcon();
                                      if (mounted) {
                                        Navigator.of(context).pop();
                                      }
                                    },
                              child: _saving
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text(l10n.save ?? 'Save'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ); // closes Material return
        }, // closes scrollController builder
      ); // closes DraggableScrollableSheet return
    }, // closes setModalState builder
      ), // closes StatefulBuilder
    ); // closes showModalBottomSheet
  }

  Color _parseColor(String colorString) {
    // Remove # if present
    String hex = colorString.replaceFirst('#', '');
    // Add 0xFF prefix for full opacity
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    } else if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    return const Color(0xFF1976D2); // Default blue
  }

  void _showColorPicker(BuildContext context, bool isBackgroundColor, [StateSetter? setModalState]) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(isBackgroundColor 
              ? (l10n.backgroundColor ?? 'Background Color')
              : (l10n.textColor ?? 'Text Color')),
          content: SingleChildScrollView(
            child: BlockPicker(
              pickerColor: isBackgroundColor ? _bgColor : _textColor,
              onColorChanged: (color) {
                setState(() {
                  if (isBackgroundColor) {
                    _bgColor = color;
                  } else {
                    _textColor = color;
                  }
                });
                // Update modal state if provided
                if (setModalState != null) {
                  setModalState(() {});
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

// Helper widget for Paper-like container
class Paper extends StatelessWidget {
  final Widget child;

  const Paper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}
