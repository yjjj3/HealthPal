/// Pure dosage parsing: reject ambiguous ranges instead of guessing a dose.
class MedicationDose {
  static double parse(String text) {
    final input = text
        .trim()
        .replaceAll('½', '1/2')
        .replaceAll('¼', '1/4')
        .replaceAll('¾', '3/4');
    if (input == '半' || input == '半顆' || input == '半粒') return 0.5;
    final match = RegExp(
      r'^(\d+(?:\.\d+)?)(?:\s*/\s*(\d+(?:\.\d+)?))?\s*(?:顆|粒|錠|包|ml|mL|毫升)?$',
    ).firstMatch(input);
    if (match == null)
      throw const FormatException('請輸入明確的單次劑量，例如 0.5、1/2 或 5 ml。');
    final numerator = double.parse(match.group(1)!);
    final denominator = match.group(2) == null
        ? 1.0
        : double.parse(match.group(2)!);
    final result = numerator / denominator;
    if (!result.isFinite || result <= 0)
      throw const FormatException('單次劑量必須大於零。');
    return result;
  }

  static String? validate(String? value) {
    try {
      parse(value ?? '');
      return null;
    } on FormatException catch (e) {
      return e.message.toString();
    }
  }

  static int frequencyPerDay(String frequency) {
    final normalized = frequency.replaceAll(' ', '').toUpperCase();
    if (normalized.contains('需要時') ||
        normalized.contains('必要時') ||
        normalized == 'PRN')
      return 0;
    const aliases = {
      'QD': 1,
      'BID': 2,
      'TID': 3,
      'QID': 4,
      '每天一次': 1,
      '每天二次': 2,
      '每天兩次': 2,
      '每天三次': 3,
      '每天四次': 4,
      '每日一次': 1,
      '每日二次': 2,
      '每日兩次': 2,
      '每日三次': 3,
      '每日四次': 4,
    };
    if (aliases.containsKey(normalized)) return aliases[normalized]!;
    final daily = RegExp(r'^(?:每天|每日)([1-4])次$').firstMatch(normalized);
    if (daily != null) return int.parse(daily.group(1)!);
    final hourly = RegExp(r'^每(6|8|12|24)小時$').firstMatch(normalized);
    if (hourly != null) return 24 ~/ int.parse(hourly.group(1)!);
    throw const FormatException('無法確認服用頻率，請手動確認。');
  }

  static int remainingDays(num supply, num dose, String frequency) {
    final count = frequencyPerDay(frequency);
    if (!supply.isFinite ||
        !dose.isFinite ||
        supply <= 0 ||
        dose <= 0 ||
        count == 0)
      return 0;
    return (supply / (dose * count)).floor();
  }
}
