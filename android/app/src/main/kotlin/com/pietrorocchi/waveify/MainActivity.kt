package com.pietrorocchi.waveify

import com.ryanheise.audioservice.AudioServiceActivity

/**
 * Extends [AudioServiceActivity] so that the activity shares the Flutter
 * engine with the background audio service. Without it the media notification
 * cannot control the running player.
 */
class MainActivity : AudioServiceActivity()
