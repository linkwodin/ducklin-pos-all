import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/auth_provider.dart';
import 'pin_login_screen.dart';
import 'username_login_screen.dart';

class UserSelectionScreen extends StatefulWidget {
  final List<Map<String, dynamic>> users;
  final VoidCallback? onSyncRequested;

  const UserSelectionScreen({super.key, required this.users, this.onSyncRequested});

  @override
  State<UserSelectionScreen> createState() => _UserSelectionScreenState();
}

class _UserSelectionScreenState extends State<UserSelectionScreen> {
  int _refreshKey = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Top bar with sync and username login buttons
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Sync button on the left
                if (widget.onSyncRequested != null)
                  IconButton(
                    icon: const Icon(Icons.sync),
                    onPressed: widget.onSyncRequested,
                    tooltip: 'Sync Users',
                  ),
                // Username login button on the right
                IconButton(
                  icon: const Icon(Icons.person),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const UsernameLoginScreen()),
                    );
                  },
                  tooltip: 'Login with Username/Password',
                ),
              ],
            ),
          ),
          // Grid layout for users (max 5 per row)
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: _buildGridLayout(context),
              ),
            ),
          ),
          // Footer with decorative wavy pattern
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildUserAvatar(Map<String, dynamic> user) {
    final firstName = user['first_name'] ?? '';
    final lastName = user['last_name'] ?? '';
    final initials = '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'.toUpperCase();
    // Use consistent blue color instead of random
    const iconColor = Color(0xFF2196F3); // Material blue

    final iconUrl = user['icon_url']?.toString();
    if (iconUrl != null && iconUrl.isNotEmpty) {
      // Check if it's a data URI
      if (iconUrl.startsWith('data:image')) {
        final svgWidget = _buildDataUriImage(iconUrl, 20);
        if (svgWidget != null) {
          // SVG image - ensure it's circular and centered
          return ClipOval(
            child: Container(
              width: 40,
              height: 40,
              color: iconColor,
              child: svgWidget,
            ),
          );
        } else {
          // PNG/JPEG data URI
          try {
            final commaIndex = iconUrl.indexOf(',');
            if (commaIndex != -1) {
              final base64Data = iconUrl.substring(commaIndex + 1);
              final bytes = base64Decode(base64Data);
              return CircleAvatar(
                radius: 20,
                backgroundImage: MemoryImage(bytes),
                backgroundColor: iconColor,
              );
            }
          } catch (e) {
            print('Error loading data URI image: $e');
          }
        }
      } else {
        // Regular network URL - use the icon_url as-is
        // CachedNetworkImageProvider will handle caching, but will refresh if URL changes
        return CircleAvatar(
          radius: 20,
          backgroundImage: CachedNetworkImageProvider(iconUrl),
          backgroundColor: iconColor,
        );
      }
    }
    // Fallback to initials
    return CircleAvatar(
      radius: 20,
      backgroundColor: iconColor,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
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

  Widget _buildGridLayout(BuildContext context) {
    if (widget.users.isEmpty) {
      return const Center(
        child: Text(
          'No users available',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // Always use 5 columns max, but center items if less than 5
    const crossAxisCount = 5;
    
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 0.9,
      ),
      itemCount: widget.users.length,
      itemBuilder: (context, index) {
        final user = widget.users[index];
        final firstName = user['first_name'] ?? '';
        final lastName = user['last_name'] ?? '';
        final fullName = '$firstName $lastName'.trim();
        return _buildUserButton(context, user, fullName);
      },
    );
  }

  Widget _buildUserButton(BuildContext context, Map<String, dynamic> user, String fullName) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PINLoginScreen(
              userId: user['id'],
              username: user['username'],
              userName: fullName,
              userAvatar: _buildUserAvatar(user),
            ),
          ),
        );
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildUserAvatar(user),
          const SizedBox(height: 4),
          Text(
            fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    // Try PNG first, then AVIF, then fallback to text
    return Image.asset(
      'assets/images/logo.png',
      height: 40,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        // Try AVIF if PNG fails
        return Image.asset(
          'assets/images/logo.avif',
          height: 40,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // Fallback to text if both images fail to load
            return Text(
              '德靈公司',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.lightBlue[300],
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: _buildLogo(),
    );
  }
}

// Custom painter for wavy line pattern
class WavyLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.lightBlue[200]!
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    final waveLength = size.width / 4;
    final waveHeight = 8.0;

    path.moveTo(0, size.height / 2);

    for (double x = 0; x <= size.width; x += waveLength) {
      path.quadraticBezierTo(
        x + waveLength / 2,
        size.height / 2 + waveHeight,
        x + waveLength,
        size.height / 2,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

