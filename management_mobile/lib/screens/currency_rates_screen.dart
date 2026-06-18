import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/admin.dart';
import '../services/api_service.dart';
import '../widgets/async_body.dart';

class CurrencyRatesScreen extends StatefulWidget {
  const CurrencyRatesScreen({super.key});

  @override
  State<CurrencyRatesScreen> createState() => _CurrencyRatesScreenState();
}

class _CurrencyRatesScreenState extends State<CurrencyRatesScreen> {
  var _loading = true;
  var _error = '';
  List<CurrencyRate> _rates = [];

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
      final rates = await ApiService.instance.listCurrencyRates();
      if (!mounted) return;
      setState(() {
        _rates = rates;
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

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context)!;
    final code = TextEditingController();
    final rate = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.addCurrencyRate),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: code, decoration: InputDecoration(labelText: l10n.currencyCode)),
            TextField(
              controller: rate,
              decoration: InputDecoration(labelText: l10n.rateToGbp),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.add)),
        ],
      ),
    );
    if (ok == true && code.text.trim().isNotEmpty) {
      try {
        await ApiService.instance.createCurrencyRate(
          code.text.trim().toUpperCase(),
          double.tryParse(rate.text.trim()) ?? 0,
        );
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiService.instance.errorMessage(e))),
          );
        }
      }
    }
    code.dispose();
    rate.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
      body: AsyncBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _rates.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final rate = _rates[index];
              return Card(
                child: ListTile(
                  title: Text(rate.currencyCode),
                  subtitle: Text(l10n.rateLabel('${rate.rateToGbp}')),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      try {
                        await ApiService.instance.deleteCurrencyRate(rate.currencyCode);
                        _load();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(ApiService.instance.errorMessage(e))),
                          );
                        }
                      }
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
