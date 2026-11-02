import 'story_model.dart';

/// An uncertainty the reader has met, and its answer if one is known yet.
typedef StoryQuestion = ({
  StoryRecord<Uncertainty> record,
  RecordTransition? resolution,
});

/// What the reader knows at the end of [section].
///
/// A record counts once the reader has reached the section it was learned in,
/// and stops counting once a transition from a reached section supersedes,
/// retracts or resolves it. Nothing from later sections is visible, so sliding
/// back to an earlier chapter never shows a spoiler. This follows
/// `project_current` and `identity_groups` in the lab's `merge.py`, with a
/// cutoff added.
class StorySnapshot {
  StorySnapshot(this.model, this.section) {
    for (final transition in model.transitions) {
      if (_reached(transition.learnedInSectionId)) {
        transitions.add(transition);
        _transitionByTarget[transition.targetRecordId] = transition;
      }
    }
    for (final record in model.allRecords) {
      if (!_reached(record.learnedInSectionId)) continue;
      final order = model.sectionById(record.learnedInSectionId)!.order;
      for (final id in record.payload.entityIds) {
        final seen = _firstSeenOrder[id];
        if (seen == null || order < seen) _firstSeenOrder[id] = order;
      }
    }
    _groupIdentities();
  }

  final StoryModel model;

  /// The last section the reader has reached.
  final StorySection section;

  /// Transitions from reached sections, oldest first.
  final List<RecordTransition> transitions = [];

  final _transitionByTarget = <String, RecordTransition>{};
  final _firstSeenOrder = <String, int>{};
  final _canonicalIds = <String, String>{};
  final _groupMembers = <String, List<String>>{};
  final _displayNames = <String, String>{};

  bool _reached(String sectionId) {
    final order = model.sectionById(sectionId)?.order;
    return order != null && order <= section.order;
  }

  /// Whether [record] is known and not yet replaced, withdrawn or answered.
  bool isActive(StoryRecord record) =>
      _reached(record.learnedInSectionId) &&
      !_transitionByTarget.containsKey(record.id);

  /// Whether the reader learned [record] in [section] itself.
  bool isNewRecord(StoryRecord record) =>
      record.learnedInSectionId == section.id;

  Iterable<StoryRecord<P>> _active<P extends RecordPayload>(
    List<StoryRecord<P>> records,
  ) => records.where(isActive);

  /// Joins entities linked by active explicit identity links of the same kind.
  void _groupIdentities() {
    final parent = <String, String>{};
    String find(String entityId) {
      var id = entityId;
      while ((parent[id] ??= id) != id) {
        id = parent[id]!;
      }
      return id;
    }

    for (final record in _active(model.identityLinks)) {
      final link = record.payload;
      final left = model.entities[link.leftEntityId];
      final right = model.entities[link.rightEntityId];
      if (link.assertion == Assertion.explicit &&
          left != null &&
          right != null &&
          left.id != right.id &&
          left.kind == right.kind) {
        parent[find(left.id)] = find(right.id);
      }
    }

    final groups = <String, List<String>>{};
    for (final id in parent.keys.toList()) {
      groups.putIfAbsent(find(id), () => []).add(id);
    }
    for (final members in groups.values) {
      if (members.length < 2) continue;
      // The earliest-introduced member represents the group, as in the lab.
      members.sort((a, b) {
        final byRevision = model.entities[a]!.introducedRevision.compareTo(
          model.entities[b]!.introducedRevision,
        );
        return byRevision != 0 ? byRevision : a.compareTo(b);
      });
      for (final id in members) {
        _canonicalIds[id] = members.first;
      }
      _groupMembers[members.first] = members;
    }
  }

  /// The entity that represents [entityId] once identities are revealed.
  String canonicalId(String entityId) => _canonicalIds[entityId] ?? entityId;

  /// Every entity revealed to be the same as [entityId], itself included.
  List<String> membersOf(String entityId) =>
      _groupMembers[canonicalId(entityId)] ?? [entityId];

  bool _isMember(String entityId, String of) =>
      canonicalId(entityId) == canonicalId(of);

  bool _mentions(StoryRecord record, String entityId) =>
      record.payload.entityIds.any((id) => _isMember(id, entityId));

  /// Section order where the reader first met [entityId], or null if not yet.
  int? firstSeenOrder(String entityId) {
    int? first;
    for (final id in membersOf(entityId)) {
      final order = _firstSeenOrder[id];
      if (order != null && (first == null || order < first)) first = order;
    }
    return first;
  }

  /// The section where the reader first met [entityId].
  StorySection firstSeenSection(String entityId) {
    final order = firstSeenOrder(entityId);
    return model.sections.firstWhere((s) => s.order == order);
  }

  /// Whether the reader first met [entityId] in [section] itself.
  bool isNewEntity(String entityId) =>
      firstSeenOrder(entityId) == section.order;

  /// Entities the reader has met, one per identity group, in order of first
  /// appearance.
  late final List<StoryEntity> knownEntities = () {
    final ids = {for (final id in _firstSeenOrder.keys) canonicalId(id)}
        .where(model.entities.containsKey)
        .toList();
    ids.sort((a, b) {
      final byOrder = firstSeenOrder(a)!.compareTo(firstSeenOrder(b)!);
      return byOrder != 0 ? byOrder : a.compareTo(b);
    });
    return [for (final id in ids) model.entities[id]!];
  }();

  /// The name the text currently uses for [entityId].
  String displayName(String entityId) =>
      _displayNames.putIfAbsent(canonicalId(entityId), () {
        final id = canonicalId(entityId);
        final names = _active(model.names)
            .where((r) => _isMember(r.payload.entityId, id))
            .toList();
        final best =
            names.where((r) => r.payload.entityId == id).lastOrNull ??
            names.lastOrNull;
        if (best != null) return best.payload.text;
        final alias = _active(model.aliases)
            .where((r) => _isMember(r.payload.entityId, id))
            .firstOrNull;
        return alias?.payload.text ?? id;
      });

  /// Other names for [entityId], including names of revealed identities.
  List<String> aliasesOf(String entityId) {
    final name = displayName(entityId);
    return {
      for (final record in [..._active(model.names), ..._active(model.aliases)])
        if (_isMember(record.payload.entityId, entityId)) record.payload.text,
    }.where((text) => text != name).toList();
  }

  List<StoryRecord<Attribute>> attributesOf(String entityId) => [
    for (final record in _active(model.attributes))
      if (_isMember(record.payload.entityId, entityId)) record,
  ];

  /// Active relationships between two different entities, oldest first.
  late final List<StoryRecord<Relationship>> relationships = [
    for (final record in _active(model.relationships))
      if (!_isMember(record.payload.sourceId, record.payload.targetId)) record,
  ];

  List<StoryRecord<Relationship>> relationshipsOf(String entityId) => [
    for (final record in relationships)
      if (_isMember(record.payload.sourceId, entityId) ||
          _isMember(record.payload.targetId, entityId))
        record,
  ];

  /// Active events, in reading order.
  late final List<StoryRecord<StoryEvent>> events =
      _active(model.events).toList()..sort((a, b) {
        final bySection = model
            .sectionById(a.learnedInSectionId)!
            .order
            .compareTo(model.sectionById(b.learnedInSectionId)!.order);
        return bySection != 0
            ? bySection
            : a.payload.narrativeOrder.compareTo(b.payload.narrativeOrder);
      });

  List<StoryRecord<StoryEvent>> eventsOf(String entityId) => [
    for (final record in events)
      if (_mentions(record, entityId)) record,
  ];

  /// Uncertainties the reader has met: open ones, and answered ones with the
  /// answer. Superseded or retracted questions are left out.
  late final List<StoryQuestion> questions = () {
    final result = <StoryQuestion>[];
    for (final record in model.uncertainties) {
      if (!_reached(record.learnedInSectionId)) continue;
      final transition = _transitionByTarget[record.id];
      if (transition == null) {
        result.add((record: record, resolution: null));
      } else if (transition.action == TransitionAction.resolve) {
        result.add((record: record, resolution: transition));
      }
    }
    return result;
  }();

  List<StoryQuestion> questionsOf(String entityId) => [
    for (final question in questions)
      if (_mentions(question.record, entityId)) question,
  ];

  /// Transitions that changed a fact about [entityId].
  List<RecordTransition> transitionsOf(String entityId) => [
    for (final transition in transitions)
      if (model.recordsById[transition.targetRecordId] case final target?
          when _mentions(target, entityId))
        transition,
  ];

  /// A one-line description of a fact, using names as of this snapshot.
  String describe(RecordPayload payload) => switch (payload) {
    EntityText(:final text) => text,
    Attribute(:final label, :final value) => '${readableLabel(label)}: $value',
    Relationship(:final sourceId, :final label, :final targetId) =>
      '${displayName(sourceId)} ${readableLabel(label)} '
          '${displayName(targetId)}',
    StoryEvent(:final description) => description,
    Uncertainty(:final question) => question,
    IdentityLink(:final explanation) => explanation,
  };

  /// A one-line description of what [transition] changed.
  String describeTransition(RecordTransition transition) {
    final target = model.recordsById[transition.targetRecordId];
    final before = target == null
        ? transition.targetRecordId
        : describe(target.payload);
    switch (transition.action) {
      case TransitionAction.supersede:
        final replacementId = transition.replacementRecordId;
        final replacement = replacementId == null
            ? null
            : model.recordsById[replacementId];
        return replacement == null
            ? 'Replaced: $before'
            : '$before → ${describe(replacement.payload)}';
      case TransitionAction.retract:
        return 'No longer holds: $before';
      case TransitionAction.resolve:
        return '$before — ${transition.resolution ?? 'answered'}';
    }
  }
}

/// Turns a snake_case label such as `member_of` into "member of".
String readableLabel(String label) => label.replaceAll('_', ' ');
