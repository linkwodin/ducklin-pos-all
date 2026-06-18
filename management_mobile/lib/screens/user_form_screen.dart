import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/store.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class UserFormScreen extends StatefulWidget {
  const UserFormScreen({super.key, this.user});

  final AdminUser? user;

  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  var _role = 'pos_user';
  var _saving = false;
  List<Store> _stores = [];
  final _selectedStoreIds = <int>{};

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _username = TextEditingController(text: user?.username ?? '');
    _password = TextEditingController();
    _firstName = TextEditingController(text: user?.firstName ?? '');
    _lastName = TextEditingController(text: user?.lastName ?? '');
    _email = TextEditingController(text: user?.email ?? '');
    _role = user?.role ?? 'pos_user';
    if (user != null) _selectedStoreIds.addAll(user.stores.map((s) => s.id));
    _loadStores();
  }

  Future<void> _loadStores() async {
    try {
      final stores = await ApiService.instance.listStores();
      if (mounted) setState(() => _stores = stores);
    } catch (_) {}
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final body = {
        'username': _username.text.trim(),
        'first_name': _firstName.text.trim(),
        'last_name': _lastName.text.trim(),
        'email': _email.text.trim(),
        'role': _role,
        if (_password.text.isNotEmpty) 'password': _password.text,
        'store_ids': _selectedStoreIds.toList(),
      };
      if (widget.user == null) {
        await ApiService.instance.createUser(body);
      } else {
        await ApiService.instance.updateUser(widget.user!.id, body);
        await ApiService.instance.updateUserStores(widget.user!.id, _selectedStoreIds.toList());
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.instance.errorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final editing = widget.user != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? l10n.editUser : l10n.newUser)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _username,
              decoration: InputDecoration(labelText: l10n.username),
              enabled: !editing,
              validator: (v) => v == null || v.trim().isEmpty ? l10n.required : null,
            ),
            if (!editing)
              TextFormField(
                controller: _password,
                decoration: InputDecoration(labelText: l10n.password),
                obscureText: true,
                validator: (v) => v == null || v.isEmpty ? l10n.required : null,
              ),
            if (editing)
              TextFormField(
                controller: _password,
                decoration: InputDecoration(labelText: l10n.newPasswordOptional),
                obscureText: true,
              ),
            TextFormField(
              controller: _firstName,
              decoration: InputDecoration(labelText: l10n.firstName),
              validator: (v) => v == null || v.trim().isEmpty ? l10n.required : null,
            ),
            TextFormField(
              controller: _lastName,
              decoration: InputDecoration(labelText: l10n.lastName),
              validator: (v) => v == null || v.trim().isEmpty ? l10n.required : null,
            ),
            TextFormField(
              controller: _email,
              decoration: InputDecoration(labelText: l10n.email),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _role,
              decoration: InputDecoration(labelText: l10n.role),
              items: [
                DropdownMenuItem(value: 'management', child: Text(l10n.roleManagement)),
                DropdownMenuItem(value: 'supervisor', child: Text(l10n.roleSupervisor)),
                DropdownMenuItem(value: 'pos_user', child: Text(l10n.rolePosUser)),
              ],
              onChanged: (v) => setState(() => _role = v ?? 'pos_user'),
            ),
            const SizedBox(height: 16),
            Text(l10n.menuStores, style: Theme.of(context).textTheme.titleSmall),
            ..._stores.map(
              (store) => CheckboxListTile(
                value: _selectedStoreIds.contains(store.id),
                title: Text(store.name),
                onChanged: (checked) => setState(() {
                  if (checked == true) {
                    _selectedStoreIds.add(store.id);
                  } else {
                    _selectedStoreIds.remove(store.id);
                  }
                }),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(editing ? l10n.saveChanges : l10n.createUser),
            ),
          ],
        ),
      ),
    );
  }
}
