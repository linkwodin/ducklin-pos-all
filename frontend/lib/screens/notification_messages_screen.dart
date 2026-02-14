import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pos_system/l10n/app_localizations.dart';

import '../providers/notification_bar_provider.dart';
import '../providers/stocktake_status_provider.dart';
import 'stocktake_flow_screen.dart';

/// Full-screen page showing recent notification messages.
/// Can optionally highlight a specific message when opened.
class NotificationMessagesScreen extends StatefulWidget {
  final String? highlightId;
  final GlobalKey<NavigatorState>? navigatorKey;

  const NotificationMessagesScreen({
    super.key,
    this.highlightId,
    this.navigatorKey,
  });

  @override
  State<NotificationMessagesScreen> createState() =>
      _NotificationMessagesScreenState();
}

class _NotificationMessagesScreenState
    extends State<NotificationMessagesScreen> {
  Timer? _flashTimer;
  Timer? _timeUpdateTimer;
  int _flashTicks = 0;
  bool _highlightOn = false;

  @override
  void initState() {
    super.initState();
    // Flash the highlighted message twice after entering (if provided).
    if (widget.highlightId != null) {
      _flashTimer = Timer.periodic(const Duration(milliseconds: 250), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() {
          _flashTicks++;
          _highlightOn = !_highlightOn;
        });
        // 4 toggles ~= 2 flashes (on->off->on->off)
        if (_flashTicks >= 4) {
          t.cancel();
          setState(() {
            _highlightOn = false;
          });
        }
      });
    }
    // Update "X ago" times every second while the drawer is visible.
    _timeUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _timeUpdateTimer?.cancel();
    super.dispose();
  }

  void _openStocktake() {
    Navigator.of(context).pop();
    widget.navigatorKey?.currentState?.push(
      MaterialPageRoute(
        builder: (_) => const StocktakeFlowScreen(type: 'day_start'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Consumer2<NotificationBarProvider, StocktakeStatusProvider>(
        builder: (context, provider, stocktakeStatus, _) {
          final items = provider.history.reversed.toList();
          final hasPendingStocktake = stocktakeStatus.hasPendingDayStartToday;
          final listLength = (hasPendingStocktake ? 1 : 0) + items.length;
          if (listLength == 0) {
            return Center(
              child: const Text('No notifications', style: TextStyle(fontSize: 16)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: listLength,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (hasPendingStocktake && index == 0) {
                return Material(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: _openStocktake,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: Row(
                        children: [
                          Icon(Icons.checklist_rounded, size: 22, color: Colors.orange.shade900),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.stocktakePendingMessage,
                              style: TextStyle(fontSize: 14, color: Colors.orange.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              final itemIndex = index - (hasPendingStocktake ? 1 : 0);
              final item = items[itemIndex];
              final isHighlighted =
                  widget.highlightId != null && widget.highlightId == item.id;

              Color? chipColor;
              if (item.isError) chipColor = Colors.red.shade50;
              if (item.isSuccess) chipColor = Colors.green.shade50;

              final baseBorder = BorderRadius.circular(8);

              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isHighlighted && _highlightOn
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.08)
                      : chipColor ?? Theme.of(context).colorScheme.surface,
                  borderRadius: baseBorder,
                  border: Border.all(
                    color: isHighlighted
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item.isError
                          ? Icons.error_outline
                          : (item.isSuccess
                              ? Icons.check_circle_outline
                              : Icons.info_outline),
                      size: 20,
                      color: item.isError
                          ? Colors.red.shade700
                          : (item.isSuccess
                              ? Colors.green.shade700
                              : Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.fullMessage ?? item.message,
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            // Simple relative time; you can replace with something richer.
                            _formatTime(item.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () =>
                          context.read<NotificationBarProvider>().dismiss(
                                item.id,
                              ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    }
    return '${diff.inDays}d ago';
  }
}

