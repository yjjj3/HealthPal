import 'dart:convert';

Map<String, dynamic> decodeAIObject(String content) {
  var value = content.trim();
  final fence = RegExp(
    r'^```(?:json)?\s*([\s\S]*?)\s*```$',
    caseSensitive: false,
  ).firstMatch(value);
  if (fence != null) value = fence.group(1)!;
  final decoded = jsonDecode(value);
  if (decoded is! Map<String, dynamic>)
    throw const FormatException('AI 回應必須是 JSON 物件。');
  return decoded;
}

String requiredText(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! String || value.trim().isEmpty)
    throw FormatException('請確認 $key 欄位。');
  return value; // Preserve OCR warning text verbatim.
}

double nonNegativeNumber(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! num || !value.isFinite || value < 0)
    throw FormatException('$key 必須是非負有限數值。');
  return value.toDouble();
}

Map<String, dynamic> strictObject(Map<String, dynamic> properties) => {
  'type': 'object',
  'properties': properties,
  'required': properties.keys.toList(),
  'additionalProperties': false,
};
Map<String, dynamic> structuredFormat(
  String name,
  Map<String, dynamic> schema,
) => {
  'type': 'json_schema',
  'json_schema': {'name': name, 'strict': true, 'schema': schema},
};
