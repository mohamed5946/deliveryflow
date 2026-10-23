/// Shared money formatting (v27.4): thousands separators, no trailing
/// `.0`, two decimals only when the value actually has a fraction —
/// the same presentation the weekly report's salary card has always
/// used, extracted so Home and the PDF export format money identically.
String formatMoney(double v) {
  final s = v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
  final parts = s.split('.');
  final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  return parts.length > 1 ? '$intPart.${parts[1]}' : intPart;
}
