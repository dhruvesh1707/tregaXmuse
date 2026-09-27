/// Lightweight formatting helpers shared across the app.
String formatINR(num amount) {
  // TODO: switch to intl NumberFormat with Indian digit grouping
  // (e.g. 1,38,000) once locale rules are confirmed with design.
  return '₹${amount.toStringAsFixed(0)}';
}

/// Like [formatINR] but keeps paise — for split amounts like the ₹49.50
/// delivery share. Trailing zero paise are trimmed (₹50, not ₹50.00).
String formatINRPaise(num amount) {
  final s = amount.toStringAsFixed(2);
  final trimmed = s.endsWith('00') ? s.substring(0, s.length - 3) : s;
  return '₹$trimmed';
}

String timeAgo(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inDays >= 30) return '${diff.inDays ~/ 30}mo ago';
  if (diff.inDays > 0) return '${diff.inDays}d ago';
  if (diff.inHours > 0) return '${diff.inHours}h ago';
  if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
  return 'Just now';
}

