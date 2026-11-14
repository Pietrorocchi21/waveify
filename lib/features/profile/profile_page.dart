import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:waveify/core/providers/app_providers.dart';
import 'package:waveify/shared/widgets/common.dart';
import 'profile_controller.dart';

/// The public profile of a user, with the follow button.
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(profileControllerProvider.notifier)
          .load(widget.userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final state = ref.watch(profileControllerProvider);
    final controller = ref.read(profileControllerProvider.notifier);
    final profile = state.profile;

    return Scaffold(
      appBar: AppBar(title: Text(t('profile.title'))),
      body: state.isLoading && profile == null
          ? const LoadingState()
          : profile == null
              ? ErrorState(
                  message: state.error ?? t('error_screen.title'),
                  onRetry: () => controller.load(widget.userId),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundImage: profile.user.avatarUrl == null
                              ? null
                              : NetworkImage(profile.user.avatarUrl!),
                          child: profile.user.avatarUrl == null
                              ? Text(
                                  profile.user.displayLabel.characters.first,
                                  style: theme.textTheme.titleLarge,
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.user.displayName ??
                                    profile.user.displayLabel,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (profile.user.username != null)
                                Text(
                                  '@${profile.user.username}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.textTertiary,
                                  ),
                                ),
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                onPressed: controller.toggleFollow,
                                icon: Icon(
                                  state.isFollowing
                                      ? Icons.check_rounded
                                      : Icons.person_add_alt_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                  state.isFollowing
                                      ? t('profile.following')
                                      : t('profile.follow'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (profile.user.bio != null &&
                        profile.user.bio!.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(profile.user.bio!, style: theme.textTheme.bodyMedium),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _Stat(
                          value: '${profile.followersCount}',
                          label: t('profile.stat_followers'),
                        ),
                        const SizedBox(width: 24),
                        _Stat(
                          value: '${profile.followingCount}',
                          label: t('profile.stat_following'),
                        ),
                      ],
                    ),
                    if (state.playlists.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      SectionHeader(title: t('profile.playlists')),
                      for (final playlist in state.playlists)
                        ListTile(
                          leading: const Icon(Icons.queue_music_rounded),
                          title: Text(playlist.title),
                          subtitle: playlist.description == null
                              ? null
                              : Text(
                                  playlist.description!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => context.push(
                            '/library/playlist'
                            '?id=${Uri.encodeQueryComponent(playlist.id)}',
                          ),
                        ),
                    ],
                  ],
                ),
    );
  }
}

/// One statistic of the profile.
class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.textTertiary),
        ),
      ],
    );
  }
}
