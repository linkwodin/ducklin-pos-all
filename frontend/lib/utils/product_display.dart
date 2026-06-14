String productDisplayName(Map<String, dynamic> product, String lang) {
  if (lang.startsWith('zh')) {
    final zh = product['name_chinese']?.toString().trim();
    if (zh != null && zh.isNotEmpty) return zh;
  }
  final name = product['name']?.toString().trim();
  if (name != null && name.isNotEmpty) return name;
  final id = product['id'];
  return id != null ? 'Product #$id' : 'Product';
}
