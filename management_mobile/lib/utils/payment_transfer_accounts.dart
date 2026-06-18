const defaultPaymentTransferAccount = 'Default account';

List<String> paymentTransferAccountOptions(String? raw) {
  final lines = (raw ?? '')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.length > 1) return lines.sublist(1);
  if (lines.isNotEmpty) return lines;
  return [defaultPaymentTransferAccount];
}
