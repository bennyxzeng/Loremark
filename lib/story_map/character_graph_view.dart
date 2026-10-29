import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../story_model/story_model.dart';
import '../story_model/story_snapshot.dart';

/// Node positions for the relationship graph.
///
/// Each connected group of nodes gets a force-directed (Fruchterman–Reingold)
/// layout with a fixed seed, so the same graph always gets the same picture.
/// The groups are then packed in rows, biggest first, so a small group can't
/// drift far away and shrink the rest when the graph is fitted to the screen.
class GraphLayout {
  const GraphLayout(this.positions, this.size);

  factory GraphLayout.compute(
    List<String> nodes,
    List<(String, String)> edges, {
    double edgeLength = 130,
    double padding = 70,
    double gap = 80,
  }) {
    if (nodes.isEmpty) return const GraphLayout({}, Size.zero);

    final neighbours = {for (final node in nodes) node: <String>{}};
    for (final (from, to) in edges) {
      if (from == to ||
          !neighbours.containsKey(from) ||
          !neighbours.containsKey(to)) {
        continue;
      }
      neighbours[from]!.add(to);
      neighbours[to]!.add(from);
    }
    final components = <List<String>>[];
    final seen = <String>{};
    for (final node in nodes) {
      if (!seen.add(node)) continue;
      final component = [node];
      for (var i = 0; i < component.length; i++) {
        for (final next in neighbours[component[i]]!) {
          if (seen.add(next)) component.add(next);
        }
      }
      components.add(component..sort());
    }
    components.sort(
      (a, b) => a.length != b.length
          ? b.length.compareTo(a.length)
          : a.first.compareTo(b.first),
    );

    final parts = [
      for (final component in components)
        _layoutComponent(component, neighbours, edgeLength),
    ];
    final area = parts.fold(
      0.0,
      (sum, part) => sum + part.$2.width * part.$2.height,
    );
    final rowWidth = math.max(
      math.sqrt(area) * 1.3,
      parts.map((part) => part.$2.width).reduce(math.max),
    );

    final positions = <String, Offset>{};
    var x = 0.0, y = 0.0, rowHeight = 0.0, width = 0.0;
    for (final (local, size) in parts) {
      if (x > 0 && x + size.width > rowWidth) {
        x = 0;
        y += rowHeight + gap;
        rowHeight = 0;
      }
      for (final MapEntry(:key, :value) in local.entries) {
        positions[key] = value + Offset(x + padding, y + padding);
      }
      width = math.max(width, x + size.width);
      rowHeight = math.max(rowHeight, size.height);
      x += size.width + gap;
    }
    return GraphLayout(
      positions,
      Size(width + 2 * padding, y + rowHeight + 2 * padding),
    );
  }

  /// Positions of one connected component, starting at the origin, and the
  /// size they take up.
  static (Map<String, Offset>, Size) _layoutComponent(
    List<String> nodes,
    Map<String, Set<String>> neighbours,
    double edgeLength,
  ) {
    final count = nodes.length;
    final side = edgeLength * math.sqrt(count);
    final random = math.Random(42);
    final positions = [
      for (var i = 0; i < count; i++)
        Offset(random.nextDouble() * side, random.nextDouble() * side),
    ];
    final indexOf = {for (var i = 0; i < count; i++) nodes[i]: i};
    final links = [
      for (var i = 0; i < count; i++)
        for (final next in neighbours[nodes[i]]!)
          if (indexOf[next]! > i) (i, indexOf[next]!),
    ];

    const iterations = 300;
    for (var step = 0; step < iterations; step++) {
      final moves = List.filled(count, Offset.zero);
      for (var i = 0; i < count; i++) {
        for (var j = i + 1; j < count; j++) {
          final delta = positions[i] - positions[j];
          final distance = math.max(delta.distance, 0.01);
          final push = delta / distance * (edgeLength * edgeLength / distance);
          moves[i] += push;
          moves[j] -= push;
        }
      }
      for (final (i, j) in links) {
        final delta = positions[i] - positions[j];
        final distance = math.max(delta.distance, 0.01);
        final pull = delta / distance * (distance * distance / edgeLength);
        moves[i] -= pull;
        moves[j] += pull;
      }
      final temperature = math.max(side / 10 * (1 - step / iterations), 1.0);
      for (var i = 0; i < count; i++) {
        final length = moves[i].distance;
        if (length > 0) {
          positions[i] += moves[i] / length * math.min(length, temperature);
        }
      }
    }

    final left = positions.map((p) => p.dx).reduce(math.min);
    final top = positions.map((p) => p.dy).reduce(math.min);
    final right = positions.map((p) => p.dx).reduce(math.max);
    final bottom = positions.map((p) => p.dy).reduce(math.max);
    final origin = Offset(left, top);
    return (
      {for (var i = 0; i < count; i++) nodes[i]: positions[i] - origin},
      Size(right - left, bottom - top),
    );
  }

  final Map<String, Offset> positions;
  final Size size;
}

/// The Story Map's relationship graph as of [snapshot] (UC5).
///
/// Node positions come from the whole model, not just the snapshot, so nodes
/// stay in place while the reader moves the chapter slider; earlier chapters
/// only hide what the reader has not met yet.
class CharacterGraphView extends StatefulWidget {
  const CharacterGraphView({
    super.key,
    required this.snapshot,
    required this.onEntityTap,
  });

  final StorySnapshot snapshot;
  final ValueChanged<String> onEntityTap;

  @override
  State<CharacterGraphView> createState() => _CharacterGraphViewState();
}

class _CharacterGraphViewState extends State<CharacterGraphView> {
  bool _showGroups = false;
  bool _showPlaces = false;
  final _layouts = <(bool, bool), GraphLayout>{};
  final _view = TransformationController();
  GraphLayout? _viewLayout;
  Size? _viewSize;

  StoryModel get _model => widget.snapshot.model;

  @override
  void didUpdateWidget(CharacterGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.model != _model) _layouts.clear();
  }

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  /// Fits the whole graph on screen. Only a new layout or screen size resets
  /// the view, so moving the chapter slider keeps the reader's zoom.
  void _fitView(GraphLayout layout, Size viewport) {
    if (identical(layout, _viewLayout) && viewport == _viewSize) return;
    _viewLayout = layout;
    _viewSize = viewport;
    // Screen margin for names that stick out past the nodes at the edges.
    const margin = 48.0;
    final scale = math.min(
      1.0,
      math.min(
        (viewport.width - 2 * margin) / layout.size.width,
        (viewport.height - margin) / layout.size.height,
      ),
    );
    // Scaled on all three axes, as InteractiveViewer does, so that
    // getMaxScaleOnAxis reads back the zoom.
    _view.value = Matrix4.diagonal3Values(scale, scale, scale)
      ..setTranslationRaw(
        (viewport.width - layout.size.width * scale) / 2,
        (viewport.height - margin - layout.size.height * scale) / 2,
        0,
      );
  }

  bool _isShown(String entityId) => switch (_model.entities[entityId]?.kind) {
    EntityKind.character => true,
    EntityKind.organization => _showGroups,
    EntityKind.location => _showPlaces,
    null => false,
  };

  GraphLayout _layout() => _layouts.putIfAbsent((_showGroups, _showPlaces), () {
    final edges = [
      for (final record in _model.relationships)
        if (_isShown(record.payload.sourceId) &&
            _isShown(record.payload.targetId))
          (record.payload.sourceId, record.payload.targetId),
    ];
    final nodes = {
      for (final (from, to) in edges) ...[from, to],
    }.toList()..sort();
    return GraphLayout.compute(nodes, edges);
  });

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final layout = _layout();
    final relationships = [
      for (final record in snapshot.relationships)
        if (_isShown(record.payload.sourceId) &&
            _isShown(record.payload.targetId))
          record,
    ];
    final degrees = <String, int>{};
    for (final record in relationships) {
      for (final id in [record.payload.sourceId, record.payload.targetId]) {
        degrees.update(
          snapshot.canonicalId(id),
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }
    }
    final nodes = <String, _GraphNode>{
      for (final MapEntry(key: id, value: degree) in degrees.entries)
        if (layout.positions[id] case final position?)
          id: _GraphNode(
            id: id,
            label: snapshot.displayName(id),
            kind: _model.entities[id]!.kind,
            center: position,
            degree: degree,
            isNew: snapshot.isNewEntity(id),
          ),
    };
    final edges = _edges(relationships, nodes);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Groups'),
                selected: _showGroups,
                onSelected: (value) => setState(() => _showGroups = value),
              ),
              FilterChip(
                label: const Text('Places'),
                selected: _showPlaces,
                onSelected: (value) => setState(() => _showPlaces = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: nodes.isEmpty
              ? const Center(child: Text('No characters introduced yet.'))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    _fitView(layout, constraints.biggest);
                    return InteractiveViewer(
                      transformationController: _view,
                      constrained: false,
                      minScale: 0.1,
                      maxScale: 4,
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      child: SizedBox.fromSize(
                        size: layout.size,
                        child: GestureDetector(
                          onTapUp: (details) =>
                              _onTap(details.localPosition, nodes.values),
                          child: CustomPaint(
                            painter: _GraphPainter(
                              nodes: nodes.values.toList(),
                              edges: edges,
                              view: _view,
                              colors: theme.colorScheme,
                              textStyle:
                                  theme.textTheme.bodySmall ??
                                  const TextStyle(),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Bold outline: new in ${snapshot.section.label} · '
            'Dashed: in the past · Tap a name for its card · Pinch to zoom',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  List<_GraphEdge> _edges(
    List<StoryRecord<Relationship>> relationships,
    Map<String, _GraphNode> nodes,
  ) {
    final snapshot = widget.snapshot;
    // Edges between the same two nodes are spread apart so labels don't stack.
    final byPair = <(String, String), List<StoryRecord<Relationship>>>{};
    for (final record in relationships) {
      final from = snapshot.canonicalId(record.payload.sourceId);
      final to = snapshot.canonicalId(record.payload.targetId);
      if (!nodes.containsKey(from) || !nodes.containsKey(to)) continue;
      final pair = from.compareTo(to) < 0 ? (from, to) : (to, from);
      byPair.putIfAbsent(pair, () => []).add(record);
    }

    return [
      for (final MapEntry(key: (first, second), value: records)
          in byPair.entries)
        for (final (index, record) in records.indexed)
          _GraphEdge(
            from: nodes[snapshot.canonicalId(record.payload.sourceId)]!.center,
            to: nodes[snapshot.canonicalId(record.payload.targetId)]!.center,
            normal: _normal(nodes[first]!.center, nodes[second]!.center),
            lane: index - (records.length - 1) / 2,
            label: readableLabel(record.payload.label),
            isPast: record.payload.temporalContext == TemporalContext.past,
            isInferred: record.payload.assertion != Assertion.explicit,
            isNew: snapshot.isNewRecord(record),
          ),
    ];
  }

  static Offset _normal(Offset from, Offset to) {
    final delta = to - from;
    final length = delta.distance;
    return length == 0 ? Offset.zero : Offset(-delta.dy, delta.dx) / length;
  }

  /// Opens the node closest to [position] among those whose shape or name
  /// was tapped.
  void _onTap(Offset position, Iterable<_GraphNode> nodes) {
    final metrics = _GraphMetrics(_view.value.getMaxScaleOnAxis());
    _GraphNode? closest;
    for (final node in nodes) {
      if (!metrics.hitArea(node.center).contains(position)) continue;
      if (closest == null ||
          (node.center - position).distance <
              (closest.center - position).distance) {
        closest = node;
      }
    }
    if (closest != null) widget.onEntityTap(closest.id);
  }
}

class _GraphNode {
  const _GraphNode({
    required this.id,
    required this.label,
    required this.kind,
    required this.center,
    required this.degree,
    required this.isNew,
  });

  final String id;
  final String label;
  final EntityKind kind;
  final Offset center;

  /// Number of relationships shown for this node.
  final int degree;
  final bool isNew;
}

class _GraphEdge {
  const _GraphEdge({
    required this.from,
    required this.to,
    required this.normal,
    required this.lane,
    required this.label,
    required this.isPast,
    required this.isInferred,
    required this.isNew,
  });

  final Offset from;
  final Offset to;

  /// Unit vector across the line, and how many lanes to move along it when
  /// several edges join the same two nodes.
  final Offset normal;
  final double lane;
  final String label;
  final bool isPast;
  final bool isInferred;
  final bool isNew;
}

/// Sizes in canvas units for the current zoom [scale].
///
/// Like a map, shapes and names shrink as the reader zooms out, but never
/// below a readable size on screen and never above their size at 100%.
class _GraphMetrics {
  _GraphMetrics(double scale)
    : point = 1 / scale,
      radius = _screen(18, 7, scale),
      nameSize = _screen(12, 9.5, scale),
      labelSize = _screen(10, 8.5, scale);

  /// One screen point.
  final double point;
  final double radius;
  final double nameSize;
  final double labelSize;

  static double _screen(double size, double minimum, double scale) =>
      (size * scale).clamp(minimum, size) / scale;

  Rect hitArea(Offset center) => Rect.fromLTRB(
    center.dx - 50 * point,
    center.dy - radius - 4 * point,
    center.dx + 50 * point,
    center.dy + radius + 2.6 * nameSize,
  );
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.nodes,
    required this.edges,
    required this.view,
    required this.colors,
    required this.textStyle,
  }) : super(repaint: view);

  final List<_GraphNode> nodes;
  final List<_GraphEdge> edges;
  final TransformationController view;
  final ColorScheme colors;

  /// The app's text style, which a canvas does not inherit on its own.
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final metrics = _GraphMetrics(view.value.getMaxScaleOnAxis());
    for (final edge in edges) {
      _paintEdge(canvas, edge, metrics);
    }
    for (final node in nodes) {
      _paintNode(canvas, node, metrics);
    }

    // A label is skipped if it would overlap one already drawn, so zooming
    // out thins labels out instead of piling them up. Well-connected and new
    // names go first, then relationship labels.
    final taken = <Rect>[];
    final byPriority = [...nodes]
      ..sort((a, b) {
        if (a.degree != b.degree) return b.degree.compareTo(a.degree);
        if (a.isNew != b.isNew) return a.isNew ? -1 : 1;
        return a.label.compareTo(b.label);
      });
    for (final node in byPriority) {
      _paintName(canvas, node, metrics, taken);
    }
    for (final edge in edges) {
      _paintEdgeLabel(canvas, edge, metrics, taken);
    }
  }

  /// Paints [text] on a light box whose top edge is centered on [topCenter],
  /// unless the box would overlap one in [taken].
  void _paintLabel(
    Canvas canvas,
    TextPainter text,
    Offset topCenter,
    _GraphMetrics metrics,
    List<Rect> taken,
  ) {
    final box = Rect.fromLTWH(
      topCenter.dx - text.width / 2 - 3 * metrics.point,
      topCenter.dy,
      text.width + 6 * metrics.point,
      text.height + 2 * metrics.point,
    );
    if (taken.any(box.overlaps)) return;
    taken.add(box);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, Radius.circular(3 * metrics.point)),
      Paint()..color = colors.surface.withValues(alpha: 0.85),
    );
    text.paint(canvas, box.topLeft + Offset(3, 1) * metrics.point);
  }

  Offset _shift(_GraphEdge edge, _GraphMetrics metrics) =>
      edge.normal * (edge.lane * 14 * metrics.point);

  Color _edgeColor(_GraphEdge edge) => edge.isNew
      ? colors.primary
      : colors.outline.withValues(alpha: edge.isInferred ? 0.45 : 0.9);

  void _paintEdge(Canvas canvas, _GraphEdge edge, _GraphMetrics metrics) {
    final delta = edge.to - edge.from;
    if (delta.distance == 0) return;
    final direction = delta / delta.distance;
    final shift = _shift(edge, metrics);
    final start = edge.from + direction * metrics.radius + shift;
    final end =
        edge.to - direction * (metrics.radius + 3 * metrics.point) + shift;
    final color = _edgeColor(edge);
    final paint = Paint()
      ..color = color
      ..strokeWidth = (edge.isNew ? 2 : 1.2) * metrics.point
      ..style = PaintingStyle.stroke;

    if (edge.isPast) {
      final length = (end - start).distance;
      final dash = 6 * metrics.point, step = 10 * metrics.point;
      for (var at = 0.0; at < length; at += step) {
        canvas.drawLine(
          start + direction * at,
          start + direction * math.min(at + dash, length),
          paint,
        );
      }
    } else {
      canvas.drawLine(start, end, paint);
    }

    final back = end - direction * (9 * metrics.point);
    final side = Offset(-direction.dy, direction.dx) * (4 * metrics.point);
    final arrow = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo((back + side).dx, (back + side).dy)
      ..lineTo((back - side).dx, (back - side).dy)
      ..close();
    canvas.drawPath(arrow, Paint()..color = color);
  }

  /// Draws the relationship name, unless the line is too short on screen.
  void _paintEdgeLabel(
    Canvas canvas,
    _GraphEdge edge,
    _GraphMetrics metrics,
    List<Rect> taken,
  ) {
    final text = _text(
      edge.label,
      textStyle.copyWith(
        fontSize: metrics.labelSize,
        color: edge.isNew ? colors.primary : colors.onSurfaceVariant,
      ),
      maxWidth: 110 * metrics.point,
    );
    final length = (edge.to - edge.from).distance;
    if (length < text.width + 2 * metrics.radius + 8 * metrics.point) return;

    final middle = (edge.from + edge.to) / 2 + _shift(edge, metrics);
    _paintLabel(
      canvas,
      text,
      middle - Offset(0, text.height / 2 + metrics.point),
      metrics,
      taken,
    );
  }

  void _paintNode(Canvas canvas, _GraphNode node, _GraphMetrics metrics) {
    final r = metrics.radius;
    final c = node.center;
    final path = switch (node.kind) {
      EntityKind.character =>
        Path()..addOval(Rect.fromCircle(center: c, radius: r)),
      EntityKind.organization =>
        Path()..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: 2.2 * r, height: 1.6 * r),
            Radius.circular(0.35 * r),
          ),
        ),
      EntityKind.location =>
        Path()
          ..moveTo(c.dx, c.dy - r)
          ..lineTo(c.dx + r, c.dy)
          ..lineTo(c.dx, c.dy + r)
          ..lineTo(c.dx - r, c.dy)
          ..close(),
    };
    final fill = switch (node.kind) {
      EntityKind.character => colors.primaryContainer,
      EntityKind.organization => colors.secondaryContainer,
      EntityKind.location => colors.tertiaryContainer,
    };
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (node.isNew ? 3 : 1) * metrics.point
        ..color = node.isNew ? colors.primary : colors.outline,
    );
  }

  void _paintName(
    Canvas canvas,
    _GraphNode node,
    _GraphMetrics metrics,
    List<Rect> taken,
  ) {
    final name = _text(
      node.label,
      textStyle.copyWith(
        fontSize: metrics.nameSize,
        color: colors.onSurface,
        fontWeight: node.isNew ? FontWeight.w700 : FontWeight.w500,
      ),
      maxWidth: 110 * metrics.point,
      maxLines: 2,
    );
    _paintLabel(
      canvas,
      name,
      node.center + Offset(0, metrics.radius + 2 * metrics.point),
      metrics,
      taken,
    );
  }

  TextPainter _text(
    String text,
    TextStyle style, {
    required double maxWidth,
    int maxLines = 1,
  }) => TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    maxLines: maxLines,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);

  @override
  bool shouldRepaint(_GraphPainter oldDelegate) =>
      oldDelegate.nodes != nodes ||
      oldDelegate.edges != edges ||
      oldDelegate.colors != colors ||
      oldDelegate.textStyle != textStyle;
}
