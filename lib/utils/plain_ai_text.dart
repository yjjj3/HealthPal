String plainAIText(String text) => text
    .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
    .replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (match) => match.group(1)!)
    .replaceAllMapped(RegExp(r'\*([^*]+)\*'), (match) => match.group(1)!)
    .replaceAll(RegExp(r'^[-*]\s+', multiLine: true), '• ')
    .trim();
