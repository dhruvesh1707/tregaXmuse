import 'package:dio/dio.dart';

/// PIN code → city/state lookup via the free India Post API.
///
/// No API key, no account: `GET api.postalpincode.in/pincode/<pin>`
/// returns the post offices for that PIN; the first office's `District`
/// is the city and `State` is the state. Returns null for an unknown PIN
/// or any failure (no network, bad response) — callers keep the fields
/// manually editable in that case, so a failed lookup never blocks the
/// form.
Future<({String city, String state})?> lookupCityState(
  String pincode,
) async {
  final pin = pincode.trim();
  if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(pin)) return null;
  try {
    final response = await Dio().get(
      'https://api.postalpincode.in/pincode/$pin',
      options: Options(
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    final body = response.data;
    if (body is! List || body.isEmpty) return null;
    final first = body.first;
    if (first is! Map || first['Status'] != 'Success') return null;
    final offices = first['PostOffice'];
    if (offices is! List || offices.isEmpty) return null;
    final office = offices.first;
    if (office is! Map) return null;
    final district = office['District'] as String?;
    final state = office['State'] as String?;
    if (district == null ||
        district.isEmpty ||
        state == null ||
        state.isEmpty) {
      return null;
    }
    return (city: district, state: state);
  } catch (_) {
    return null;
  }
}
