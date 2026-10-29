import 'package:flutter/material.dart';

import '../story_model/story_model.dart';
import '../story_model/story_snapshot.dart';

/// Searchable list of the characters the reader has met (UC4 1a).
class CharacterListView extends StatefulWidget {
  const CharacterListView({
    super.key,
    required this.snapshot,
    required this.onEntityTap,
  });

  final StorySnapshot snapshot;
  final ValueChanged<String> onEntityTap;

  @override
  State<CharacterListView> createState() => _CharacterListViewState();
}

class _CharacterListViewState extends State<CharacterListView> {
  String _query = '';

  bool _matches(String entityId) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    final snapshot = widget.snapshot;
    return [
      snapshot.displayName(entityId),
      ...snapshot.aliasesOf(entityId),
    ].any((name) => name.toLowerCase().contains(query));
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final characters = [
      for (final entity in snapshot.knownEntities)
        if (entity.kind == EntityKind.character && _matches(entity.id)) entity,
    ];
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search characters you have met',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: characters.isEmpty
              ? Center(
                  child: Text(
                    _query.isEmpty
                        ? 'No characters introduced yet.'
                        : 'No character you have met matches “$_query”.',
                  ),
                )
              : ListView.builder(
                  itemCount: characters.length,
                  itemBuilder: (context, index) {
                    final id = characters[index].id;
                    final details = snapshot
                        .attributesOf(id)
                        .take(2)
                        .map((record) => record.payload.value);
                    return ListTile(
                      title: Text(snapshot.displayName(id)),
                      subtitle: Text(
                        [
                          snapshot.firstSeenSection(id).label,
                          ...details,
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: snapshot.isNewEntity(id)
                          ? Text(
                              'New',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            )
                          : null,
                      onTap: () => widget.onEntityTap(id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
