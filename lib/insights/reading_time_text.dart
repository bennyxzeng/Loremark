/// How long something takes to read, in the short form the bottom bar and the
/// insights sheet show: "Less than a minute", "12 min", "1 h 05 min".
String formatReadingTime(Duration time) {
  if (time < const Duration(minutes: 1)) {
    return 'Less than a minute';
  }
  final minutes = (time.inSeconds / 60).round();
  if (minutes < 60) {
    return '$minutes min';
  }
  final rest = (minutes % 60).toString().padLeft(2, '0');
  return '${minutes ~/ 60} h $rest min';
}

/// [formatReadingTime] as a spoken sentence part, for screen readers:
/// "about 12 minutes", "about 1 hour 5 minutes".
String spokenReadingTime(Duration time) {
  if (time < const Duration(minutes: 1)) {
    return 'less than a minute';
  }
  final minutes = (time.inSeconds / 60).round();
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  final parts = [
    if (hours > 0) '$hours ${hours == 1 ? 'hour' : 'hours'}',
    if (rest > 0) '$rest ${rest == 1 ? 'minute' : 'minutes'}',
  ];
  return 'about ${parts.join(' ')}';
}
