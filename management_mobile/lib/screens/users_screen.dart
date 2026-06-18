import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../utils/role_labels.dart';
import '../utils/user_avatar.dart';
import '../widgets/async_body.dart';
import 'user_form_screen.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  var _loading = true;
  var _error = '';
  List<AdminUser> _users = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final users = await ApiService.instance.listUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiService.instance.errorMessage(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const UserFormScreen()),
          );
          _load();
        },
        child: const Icon(Icons.add),
      ),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _users.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final user = _users[index];
              return Card(
                child: ListTile(
                  leading: UserAvatar.fromUser(user, radius: 22),
                  title: Text(user.displayName),
                  subtitle: Text('${user.username} · ${roleLabel(l10n, user.role)}'),
                  trailing: Chip(
                    label: Text(user.isActive ? l10n.active : l10n.inactive, style: const TextStyle(fontSize: 11)),
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => UserFormScreen(user: user)),
                    );
                    _load();
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
