import 'package:flutter_test/flutter_test.dart';
import 'package:waveify/features/lyrics/lyrics_parser.dart';
import 'package:waveify/features/lyrics/lyrics_stream.dart';
import 'package:waveify/models/lyrics.dart';

void main() {
  group('LyricsParser — LRC', () {
    test('parses simple LRC lines', () {
      const raw = '[00:12.00]First line\n[00:15.50]Second line';
      final parsed = LyricsParser.parse(raw, format: 'lrc');

      expect(parsed.syncedLines, hasLength(2));
      expect(parsed.syncedLines[0].timeMs, 12000);
      expect(parsed.syncedLines[0].text, 'First line');
      expect(parsed.syncedLines[1].timeMs, 15500);
      expect(parsed.syncedLines[1].text, 'Second line');
      expect(parsed.plainLyrics, 'First line\nSecond line');
    });

    test('parses minutes larger than 59', () {
      final parsed = LyricsParser.parse('[03:07.25]Verse', format: 'lrc');
      expect(parsed.syncedLines.single.timeMs, 3 * 60000 + 7250);
    });

    test('expands multi-timestamp lines', () {
      final parsed = LyricsParser.parse(
        '[00:10.00][01:10.00]Chorus',
        format: 'lrc',
      );
      expect(parsed.syncedLines, hasLength(2));
      expect(parsed.syncedLines[0].timeMs, 10000);
      expect(parsed.syncedLines[1].timeMs, 70000);
    });

    test('parses enhanced LRC word timings', () {
      const raw = '[00:10.00]<00:10.00>Hello <00:10.50>world';
      final parsed = LyricsParser.parse(raw, format: 'lrc');

      final line = parsed.syncedLines.single;
      expect(line.words, hasLength(2));
      expect(line.words[0].text, 'Hello');
      expect(line.words[0].timeMs, 10000);
      expect(line.words[1].text, 'world');
      expect(line.words[1].timeMs, 10500);
    });

    test('ignores metadata tags such as [ar:Artist]', () {
      final parsed = LyricsParser.parse(
        '[ar:Artist]\n[00:05.00]Real line',
        format: 'lrc',
      );
      expect(parsed.syncedLines, hasLength(1));
      expect(parsed.syncedLines.single.text, 'Real line');
    });
  });

  group('LyricsParser — richsync', () {
    test('parses the Musixmatch richsync JSON format', () {
      const raw = '[{"ts":10.5,"te":12.0,"l":[{"c":"Hello","o":10.5},'
          '{"c":" ","o":10.9},{"c":"world","o":11.0}]}]';
      final parsed = LyricsParser.parse(raw, format: 'richsync');

      final line = parsed.syncedLines.single;
      expect(line.timeMs, 10500);
      expect(line.durationMs, 1500);
      expect(line.text, 'Hello world');
      // The whitespace token is merged into the preceding word.
      expect(line.words, hasLength(2));
      expect(line.words.first.text, 'Hello ');
      expect(line.words.first.endMs, 11000);
      expect(line.words.last.text, 'world');
    });
  });

  group('LyricsParser — MXM subtitles', () {
    test('parses the MXM subtitles JSON format', () {
      const raw = '[{"time":{"total":3.25},"text":"One"},'
          '{"time":{"total":4.5},"text":"Two"}]';
      final parsed = LyricsParser.parse(raw);

      expect(parsed.syncedLines, hasLength(2));
      expect(parsed.syncedLines[0].timeMs, 3250);
      expect(parsed.syncedLines[1].text, 'Two');
    });
  });

  group('LyricsParser — TTML', () {
    test('parses timed paragraphs', () {
      const raw = '<tt><body><div>'
          '<p begin="00:00:05.000" end="00:00:08.000">Hello</p>'
          '<p begin="00:00:09.500" end="00:00:12.000">World</p>'
          '</div></body></tt>';
      final parsed = LyricsParser.parse(raw, format: 'ttml');

      expect(parsed.syncedLines, hasLength(2));
      expect(parsed.syncedLines[0].timeMs, 5000);
      expect(parsed.syncedLines[0].durationMs, 3000);
      expect(parsed.syncedLines[1].text, 'World');
    });

    test('parses timestamps expressed in plain seconds', () {
      // The providers mix `18.893` and `1:00.923` in the same file.
      const raw = '<tt><body><div>'
          '<p begin="18.893" end="22.228">First</p>'
          '<p begin="1:00.923" end="1:05.230">Second</p>'
          '</div></body></tt>';
      final parsed = LyricsParser.parse(raw, format: 'ttml');

      expect(parsed.syncedLines, hasLength(2));
      expect(parsed.syncedLines[0].timeMs, 18893);
      expect(parsed.syncedLines[1].timeMs, 60923);
    });

    test('parses the word level timings of the spans', () {
      const raw = '<tt><body><div>'
          '<p begin="18.893" end="22.228">'
          '<span begin="18.893" end="19.255">We\'re</span> '
          '<span begin="19.255" end="19.538">no</span> '
          '<span begin="19.538" end="20.071">strangers</span>'
          '</p></div></body></tt>';
      final parsed = LyricsParser.parse(raw, format: 'ttml');

      final line = parsed.syncedLines.single;
      expect(line.text, "We're no strangers");
      expect(line.words, hasLength(3));
      expect(line.words[0].text, "We're");
      expect(line.words[0].timeMs, 18893);
      expect(line.words[0].endMs, 19255);
      expect(line.words[1].text, 'no');
      expect(line.words[2].text, 'strangers');
    });

    test('accepts the "s" suffix', () {
      const raw = '<tt><body><div>'
          '<p begin="18.893s" end="22.228s">Timed</p>'
          '</div></body></tt>';
      final parsed = LyricsParser.parse(raw, format: 'ttml');
      expect(parsed.syncedLines.single.timeMs, 18893);
    });
  });

  group('LyricsParser — QRC', () {
    test('parses per-word timings', () {
      const raw = '[00:12.34]<0,100>Hello<200,100>world';
      final parsed = LyricsParser.parse(raw, format: 'qrc');

      final line = parsed.syncedLines.single;
      expect(line.timeMs, 12340);
      expect(line.words, hasLength(2));
      expect(line.words[0].text, 'Hello');
      expect(line.words[0].timeMs, 0);
      expect(line.words[1].text, 'world');
    });
  });

  group('LyricsParser — plain and empty', () {
    test('returns the raw text for unsynced lyrics', () {
      final parsed = LyricsParser.parse('Just some words');
      expect(parsed.syncedLines, isEmpty);
      expect(parsed.plainLyrics, 'Just some words');
    });

    test('returns an empty result for blank input', () {
      final parsed = LyricsParser.parse('   ');
      expect(parsed.syncedLines, isEmpty);
      expect(parsed.plainLyrics, isNull);
    });
  });

  group('Lyrics offset', () {
    test('shifts the lines and the words', () {
      const raw = '[00:10.00]<00:10.00>Hello';
      final parsed = LyricsParser.parse(raw, format: 'lrc');
      final shifted = parsed.offset(500);

      expect(shifted.syncedLines.single.timeMs, 10500);
      expect(shifted.syncedLines.single.words.single.timeMs, 10500);
    });

    test('never shifts a line before zero', () {
      const raw = '[00:01.00]Early';
      final parsed = LyricsParser.parse(raw, format: 'lrc');
      expect(parsed.offset(-5000).syncedLines.single.timeMs, 0);
    });
  });

  group('LyricsStreamEvent parsing', () {
    test('parses a provider-found event', () {
      final event = parseLyricsEvent({
        'type': 'provider',
        'provider': 'musixmatch',
        'status': 'found',
        'candidate': {
          'provider': 'musixmatch',
          'syncLevel': 'word_level',
          'contentKind': 'word_synced',
          'quality': {'total': 88},
          'lyrics': {'format': 'lrc', 'content': '[00:01.00]Hi'},
        },
      });

      expect(event, isA<LyricsProviderFoundEvent>());
      final found = event as LyricsProviderFoundEvent;
      expect(found.candidate.provider, 'musixmatch');
      expect(found.candidate.syncLevel, LyricsSyncLevel.wordLevel);
      expect(found.candidate.quality.total, 88);
    });

    test('parses a done event', () {
      final event = parseLyricsEvent({
        'type': 'done',
        'cached': true,
        'best': {'provider': 'lyricfind', 'quality': 70, 'syncLevel': 'line_level'},
      });

      expect(event, isA<LyricsDoneEvent>());
      final done = event as LyricsDoneEvent;
      expect(done.cached, isTrue);
      expect(done.bestProvider, 'lyricfind');
      expect(done.bestSyncLevel, LyricsSyncLevel.lineLevel);
    });

    test('ignores an unknown event type', () {
      expect(parseLyricsEvent({'type': 'whatever'}), isNull);
    });
  });
}
