import 'package:flutter_test/flutter_test.dart';
import 'package:shreyx_music/utils/music_title_normalizer.dart';

void main() {
  group('MusicTitleNormalizer Tests', () {
    test('Strips non-essential junk tags', () {
      expect(
        MusicTitleNormalizer.normalize('Blinding Lights (Official Video)'),
        equals('Blinding Lights'),
      );
      expect(
        MusicTitleNormalizer.normalize('Starboy [Official Audio] ft. Daft Punk'),
        equals('Starboy ft. Daft Punk'),
      );
      expect(
        MusicTitleNormalizer.normalize('Shape of You [Lyrics Video] (HD 4K)'),
        equals('Shape of You'),
      );
      expect(
        MusicTitleNormalizer.normalize('Kesariya - Brahmastra | Full Video Song | Ranbir, Alia'),
        equals('Kesariya - Brahmastra | Ranbir, Alia'),
      );
      expect(
        MusicTitleNormalizer.normalize('Hotel California (2013 Remastered)'),
        equals('Hotel California'),
      );
    });

    test('Preserves artistic descriptors (Remix, Live, Acoustic, etc.)', () {
      expect(
        MusicTitleNormalizer.normalize('Blinding Lights (Live at the Super Bowl)'),
        equals('Blinding Lights (Live at the Super Bowl)'),
      );
      expect(
        MusicTitleNormalizer.normalize('Perfect (Acoustic Version)'),
        equals('Perfect (Acoustic Version)'),
      );
      expect(
        MusicTitleNormalizer.normalize('Levitating (Don Diablo Remix) [Official Video]'),
        equals('Levitating (Don Diablo Remix)'),
      );
      expect(
        MusicTitleNormalizer.normalize('Save Your Tears (Slowed + Reverb)'),
        equals('Save Your Tears (Slowed + Reverb)'),
      );
      expect(
        MusicTitleNormalizer.normalize('After Hours (Sped Up)'),
        equals('After Hours (Sped Up)'),
      );
    });

    test('Extracts preserved descriptors correctly', () {
      final desc = MusicTitleNormalizer.extractDescriptors('Stay (Acoustic Live Cover)');
      expect(desc, contains('acoustic'));
      expect(desc, contains('live'));
      expect(desc, contains('cover'));
    });
  });
}
