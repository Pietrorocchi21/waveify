import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/network/catalog_service.dart';
import '../../../models/catalog.dart';
import '../../../models/track.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/track_widgets.dart';
import '../../player/player_controller.dart';

/// The global search screen.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  String _query = '';
  String _type = 'all';
  CatalogSearchSource _source = CatalogSearchSource.online;
  int _generation = 0;
  List<SearchItem> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _applyInitialQuery();
  }

  @override
  void didUpdateWidget(SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != oldWidget.initialQuery) _applyInitialQuery();
  }

  void _applyInitialQuery() {
    final query = widget.initialQuery.trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    _controller.text = query;
    _source = CatalogSearchSource.online;
    _type = 'track';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.text == query) _search(query);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _generation++;
      setState(() {
        _query = '';
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _search(value.trim());
    });
  }

  Future<void> _search(String query) async {
    final generation = ++_generation;
    final source = _source, type = _type;
    setState(() {
      _loading = true;
      _error = null;
      _query = query;
    });
    try {
      final results = await ref
          .read(catalogProvider)
          .search(query, type: type, source: source);
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (err) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = '$err';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              t('common.sidebar.search'),
              style: theme.textTheme.headlineMedium,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: _onChanged,
            onSubmitted: (value) {
              _debounce?.cancel();
              if (value.trim().isNotEmpty) _search(value.trim());
            },
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: t('search.placeholder'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                      },
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final source in const [
                    (CatalogSearchSource.online, 'Audius'),
                    (CatalogSearchSource.youtube, 'YouTube'),
                    (CatalogSearchSource.library, 'search.library'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selectedColor: theme.colorScheme.primary,
                        checkmarkColor: theme.colorScheme.onPrimary,
                        labelStyle: theme.textTheme.labelLarge?.copyWith(
                          color: _source == source.$1
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                        ),
                        label: Text(
                          source.$1 == CatalogSearchSource.library
                              ? t(source.$2)
                              : source.$2,
                        ),
                        selected: _source == source.$1,
                        onSelected: (_) {
                          setState(() => _source = source.$1);
                          if (_query.isNotEmpty) _search(_query);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in const [
                  ('all', 'search.all'),
                  ('track', 'search.songs'),
                  ('artist', 'search.artists'),
                  ('album', 'search.albums'),
                  ('playlist', 'search.playlists'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selectedColor: theme.colorScheme.primary,
                      checkmarkColor: theme.colorScheme.onPrimary,
                      labelStyle: theme.textTheme.labelLarge?.copyWith(
                        color: _type == entry.$1
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                      ),
                      label: Text(t(entry.$2)),
                      selected: _type == entry.$1,
                      onSelected: (_) {
                        setState(() => _type = entry.$1);
                        if (_query.isNotEmpty) _search(_query);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildBody(theme, t)),
      ],
    );
  }

  Widget _buildBody(ThemeData theme, dynamic t) {
    if (_query.isEmpty) {
      return EmptyState(
        icon: Icons.search_rounded,
        title: t(
          _source == CatalogSearchSource.online
              ? 'search.online_prompt'
              : 'search.type_to_search',
        ),
      );
    }
    if (_loading) return const LoadingState();
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: () => _search(_query));
    }
    if (_results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: t('search.no_results'),
      );
    }

    final tracks = _results.where((r) => r.type == 'track').toList();
    final others = _results.where((r) => r.type != 'track').toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (tracks.isNotEmpty) ...[
          SectionHeader(title: t('search.songs')),
          for (final track in tracks)
            TrackRow(
              track: track.track!,
              queue: tracks
                  .map((e) => e.track)
                  .whereType<Track>()
                  .toList(growable: false),
              context_: 'search:$_query',
            ),
        ],
        if (others.isNotEmpty) ...[
          SectionHeader(title: t('search.all')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in others)
                  _SearchResultChip(item: item, onTap: () => _openResult(item)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _openResult(SearchItem item) {
    final player = ref.read(playerControllerProvider.notifier);
    switch (item.type) {
      case 'artist':
        context.push('/artist?id=${Uri.encodeQueryComponent(item.id)}');
      case 'album':
        context.push(
          '/collection?type=album&id=${Uri.encodeQueryComponent(item.id)}',
        );
      case 'playlist':
        context.push(
          '/collection?type=playlist&id=${Uri.encodeQueryComponent(item.id)}',
        );
      default:
        final track = item.track;
        if (track != null) {
          player.playTrack(track, context: 'search:$_query');
        }
    }
  }
}

class _SearchResultChip extends StatelessWidget {
  const _SearchResultChip({required this.item, required this.onTap});

  final SearchItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPanel(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CoverImage(url: item.cover?.url ?? '', size: 32, borderRadius: 6),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.displaySubtitle.isNotEmpty)
                  Text(
                    item.displaySubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTertiary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
