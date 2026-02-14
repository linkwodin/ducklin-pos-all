import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/notification_bar_provider.dart';
import '../providers/stocktake_status_provider.dart';
import '../screens/stocktake_flow_screen.dart';
import '../screens/notification_messages_screen.dart';

/// Always-visible bottom bar. Notifications appear inside it and scroll away after 10s or when closed.
class NotificationBar extends StatefulWidget {
  const NotificationBar({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  static const double height = 56;

  @override
  State<NotificationBar> createState() => _NotificationBarState();
}

class _NotificationBarState extends State<NotificationBar> {
  Timer? _ticker;
  bool _messagesDrawerOpen = false;

  @override
  void initState() {
    super.initState();
    // Update countdown progress bars often for smooth animation (~20 fps).
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static const String _messagesRouteName = '_notification_messages_drawer';

  void _openMessages(BuildContext context, {String? highlightId}) {
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;
    // If drawer is already open, pop it then reopen with new highlightId so the tapped message flashes.
    navigator.popUntil((route) => route.settings.name != _messagesRouteName);
    if (mounted) setState(() => _messagesDrawerOpen = true);
    navigator.push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black54,
        barrierDismissible: true,
        fullscreenDialog: false,
        settings: const RouteSettings(name: _messagesRouteName),
        pageBuilder: (_, __, ___) => Align(
          alignment: Alignment.centerRight,
          child: Material(
            elevation: 8,
            child: SizedBox(
              width: 380,
              child: NotificationMessagesScreen(
                highlightId: highlightId,
                navigatorKey: widget.navigatorKey,
              ),
            ),
          ),
        ),
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;
          final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 250),
      ),
    ).then((_) {
      if (mounted) setState(() => _messagesDrawerOpen = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: NotificationBar.height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Consumer2<NotificationBarProvider, StocktakeStatusProvider>(
        builder: (context, provider, stocktakeStatus, _) {
          final auto = NotificationBarProvider.autoDismissDuration;
          final hasPendingStocktake = stocktakeStatus.hasPendingDayStartToday;
          final itemCount = 1 + (hasPendingStocktake ? 1 : 0) + provider.items.length;
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: itemCount,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index == 0) {
                return ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 120, maxWidth: 200, minHeight: 36),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openMessages(context),
                    child: Material(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_none, size: 20, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 6),
                            Text('Messages', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }
              if (hasPendingStocktake && index == 1) {
                return GestureDetector(
                  onTap: () {
                    widget.navigatorKey.currentState?.push(
                      MaterialPageRoute(
                        builder: (_) => const StocktakeFlowScreen(type: 'day_start'),
                      ),
                    );
                  },
                  child: Material(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.checklist_rounded, size: 22, color: Colors.orange.shade900),
                    ),
                  ),
                );
              }
              final itemIndex = index - 1 - (hasPendingStocktake ? 1 : 0);
                final item = provider.items[itemIndex];
                final remainingMs = provider.getRemainingMsFor(item);
                final fraction = remainingMs <= 0
                    ? 0.0
                    : (remainingMs / auto.inMilliseconds).clamp(0.0, 1.0);

                Color? bg;
                if (item.isError) bg = Colors.red.shade100;
                if (item.isSuccess) bg = Colors.green.shade100;

                return ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 200, maxWidth: 360),
                  child: MouseRegion(
                    onEnter: (_) => provider.pauseTimer(item.id),
                    onExit: (_) => provider.resumeTimer(item.id),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openMessages(context, highlightId: item.id),
                      child: Material(
                      color:
                          bg ?? Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                            item.isError
                                ? Icons.error_outline
                                : (item.isSuccess
                                    ? Icons.check_circle_outline
                                    : Icons.info_outline),
                            size: 18,
                            color: item.isError
                                ? Colors.red.shade800
                                : (item.isSuccess
                                    ? Colors.green.shade800
                                    : null),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 320),
                                  child: Text(
                                    item.message,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: item.isError
                                          ? Colors.red.shade900
                                          : (item.isSuccess
                                              ? Colors.green.shade900
                                              : null),
                                    ),
                                  ),
                                ),
                                if (!item.isPersistent) ...[
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: fraction,
                                      backgroundColor:
                                          Colors.black.withOpacity(0.06),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        item.isError
                                            ? Colors.red.shade700
                                            : (item.isSuccess
                                                ? Colors.green.shade700
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .primary),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => provider.dismiss(item.id),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ),
                );
              },
            );
          },
        ),
    );
  }
}
