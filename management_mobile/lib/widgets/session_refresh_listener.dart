import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

/// Refreshes session user data when the app returns from background.
class SessionRefreshListener extends StatefulWidget {
  const SessionRefreshListener({super.key, required this.child});

  final Widget child;

  @override
  State<SessionRefreshListener> createState() => _SessionRefreshListenerState();
}

class _SessionRefreshListenerState extends State<SessionRefreshListener> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AuthProvider>().onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
