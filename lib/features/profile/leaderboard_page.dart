import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:waveify/core/providers/app_providers.dart';
import 'package:waveify/shared/widgets/common.dart';

import 'profile_controller.dart';

/// The leaderboard: the global one and the one of an artist.
class LeaderboardPage extends ConsumerStatefulWidget {
  const LeaderboardPage({super.key, this.artistId, this.artistName});

  /// When it is set, the leaderboard of the artist is shown.
  final String? artistId;
  final String? artistName;

  @override
  ConsumerState<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends ConsumerState<LeaderboardPage> {
  String _period = 'weekly';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final controller = ref.read(leaderboardControllerProvider.notifier);
    final artistId = widget.artistId;
    if (artistId != null) {
      controller.loadArtist(artistId, period: _period);
    } else {
      controller.loadGlobal(period: _period);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final state = ref.watch(leaderboardControllerProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.artistName ?? t('leaderboard.title')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'weekly',
                  label: Text(t('leaderboard.weekly')),
                ),
                ButtonSegment(
                  value: 'monthly',
                  label: Text(t('leaderboard.monthly')),
                ),
                ButtonSegment(
                  value: 'all_time',
                  label: Text(t('leaderboard.all_time')),
                ),
              ],
              selected: {_period},
              onSelectionChanged: (value) {
                setState(() => _period = value.first);
                _load();
              },
            ),
          ),
          Expanded(
            child: state.isLoading && state.entries.isEmpty
                ? const LoadingState()
                : state.error != null && state.entries.isEmpty
                ? ErrorState(message: state.error!, onRetry: _load)
                : state.entries.isEmpty
                ? EmptyState(
                    icon: Icons.emoji_events_outlined,
                    title: t('leaderboard.empty'),
                  )
                : ListView.builder(
                    itemCount: state.entries.length,
                    itemBuilder: (context, index) {
                      final entry = state.entries[index];
                      return ListTile(
                        leading: SizedBox(
                          width: 32,
                          child: Text(
                            '${entry.rank}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: entry.rank <= 3
                                  ? theme.colorScheme.primary
                                  : theme.textTertiary,
                            ),
                          ),
                        ),
                        title: Text(entry.label),
                        subtitle: Text(
                          '${entry.playCount} ${t('leaderboard.plays')}',
                        ),
                        trailing: Text(
                          _formatDuration(entry.playedDurationMs),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTertiary,
                          ),
                        ),
                        onTap: () => context.push(
                          '/profile'
                          '?id=${Uri.encodeQueryComponent(entry.username ?? '')}',
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(int milliseconds) {
    final total = milliseconds ~/ 1000;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}
