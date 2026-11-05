/// How hard a model thinks: sent as `reasoning.effort`.
enum StoryEffort {
  none('None'),
  low('Low'),
  medium('Medium'),
  high('High'),
  xhigh('Extra high'),
  max('Max');

  const StoryEffort(this.label);

  final String label;
}

/// The effort used until the reader picks one, the lab's own default.
const defaultStoryEffort = StoryEffort.high;

/// A model the Story Map can be built with.
///
/// [providerName] is an `AiProvider`'s name. It is a string here so that this
/// file, and the update pipeline with it, needs no Flutter.
enum StoryModelChoice {
  deepseekFlash(
    id: 'deepseek-flash',
    label: 'DeepSeek Flash',
    providerName: 'deepseek',
    // DeepSeek treats medium and xhigh as high.
    efforts: [
      StoryEffort.none,
      StoryEffort.low,
      StoryEffort.high,
      StoryEffort.max,
    ],
  ),
  gpt61Terra(
    id: 'gpt-6.1-terra',
    label: 'GPT-6.1 Terra',
    providerName: 'openai',
    efforts: StoryEffort.values,
  ),
  gpt61Sol(
    id: 'gpt-6.1-sol',
    label: 'GPT-6.1 Sol',
    providerName: 'openai',
    // Sol doesn't accept `none`.
    efforts: [
      StoryEffort.low,
      StoryEffort.medium,
      StoryEffort.high,
      StoryEffort.xhigh,
      StoryEffort.max,
    ],
  );

  const StoryModelChoice({
    required this.id,
    required this.label,
    required this.providerName,
    required this.efforts,
  });

  /// The name the provider's API knows it by.
  final String id;
  final String label;
  final String providerName;
  final List<StoryEffort> efforts;

  /// The models of a provider; the first is its default.
  static List<StoryModelChoice> forProvider(String providerName) => [
    for (final model in values)
      if (model.providerName == providerName) model,
  ];

  /// The model called [id] if the provider has it, or else the provider's
  /// default, so a choice made for another provider doesn't carry over.
  static StoryModelChoice resolve(String providerName, String? id) {
    final models = forProvider(providerName);
    return models.where((model) => model.id == id).firstOrNull ?? models.first;
  }

  /// The effort called [name] if this model accepts it, or else the default.
  StoryEffort resolveEffort(String? name) =>
      efforts.where((effort) => effort.name == name).firstOrNull ??
      defaultStoryEffort;
}

/// Where a provider's Responses API is, and how its requests differ.
class StoryProvider {
  const StoryProvider._(
    this.responsesUrl, {
    required this.sendsStoreAndTruncation,
  });

  factory StoryProvider.named(String name) => switch (name) {
    'openai' => const StoryProvider._(
      'https://api.openai.com/v1/responses',
      sendsStoreAndTruncation: true,
    ),
    // DeepSeek ignores `store` and `truncation`: it never stores responses and
    // rejects over-long input with an HTTP 400.
    'deepseek' => const StoryProvider._(
      'https://api.deepseek.com/responses',
      sendsStoreAndTruncation: false,
    ),
    _ => throw ArgumentError.value(name, 'name', 'Unknown provider'),
  };

  final String responsesUrl;
  final bool sendsStoreAndTruncation;
}
