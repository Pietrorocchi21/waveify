import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../models/track.dart';
import 'common.dart';

/// Lets the user search the catalog and pick one or more tracks.
///
/// Returns the selected tracks, or an empty list when the sheet is dismissed.
Future<List<Track>> showTrackPickerSheet(
  BuildContext context, {
  String? title,
}) async {
  final result = await showModalBottomSheet<List<Track>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _TrackPickerSheet(title: title),
  );
  return result ?? const [];
}

class _TrackPickerSheet extends ConsumerStatefulWidget {
  const _TrackPickerSheet({this.title});

  final String? title;

  @override
  ConsumerState<_TrackPickerSheet> createState() => _TrackPickerSheetState();
}

class _TrackPickerSheetState extends ConsumerState<_TrackPickerSheet> {
  final _controller = TextEditingController();
  final _selected = <String, Track>{};
  Timer? _debounce;
  List<Track> _results = const [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value.trim()));
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final items = await ref.read(musicRepositoryProvider).search(query, limit: 20);
      if (!mounted) return;
      setState(() {
        _results = items
            .map((item) => Track(
                  id: item.id,
                  title: item.title,
                  artists: item.artists,
                  coverUrl: item.coverUrl,
                  durationMs: item.durationMs,
                ))
            .toList(growable: false);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title ?? t('playlist.add_tracks'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(
                            _selected.values.toList(growable: false),
                          ),
                  child: Text(
                    t('common.add'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              autofocus: true,
              decoration: InputDecoration(
                hintText: t('search.placeholder'),
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const LoadingState()
                : _results.isEmpty
                    ? EmptyState(
                        icon: Icons.search_rounded,
                        title: t('search.type_to_search'),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final track = _results[index];
                          final selected = _selected.containsKey(track.id);
                          return CheckboxListTile(
                            value: selected,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selected[track.id] = track;
                                } else {
                                  _selected.remove(track.id);
                                }
                              });
                            },
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              track.artists,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            secondary: CoverImage(
                              url: track.coverUrl,
                              size: 40,
                              borderRadius: 4,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
