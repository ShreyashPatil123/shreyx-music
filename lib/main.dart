import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/player_provider.dart';
import 'providers/search_provider.dart';
import 'providers/vault_provider.dart';
import 'screens/main_navigation.dart';
import 'services/audio_handler.dart';
import 'services/audio_normalization_service.dart';
import 'services/crossfade_audio_engine.dart';
import 'services/equalizer_service.dart';
import 'services/stream_cache_service.dart';
import 'theme/app_theme.dart';

late ShrexAudioHandler _audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system navigation & status bar colors
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D0E16),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize services (must happen before audio handler)
  await StreamCacheService().init();
  await AudioNormalizationService().init();
  await CrossfadeAudioEngine().init();
  await EqualizerService().init();

  // Initialize Native Audio Service for Background & Lock Screen Playback
  _audioHandler = await AudioService.init(
    builder: () => ShrexAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.shreyx.player.channel.audio',
      androidNotificationChannelName: 'ShreyX Music Playback',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'drawable/ic_notification',
    ),
  );

  runApp(const ShrexApp());
}

class ShrexApp extends StatelessWidget {
  const ShrexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlayerProvider(_audioHandler)),
        ChangeNotifierProvider(create: (_) => VaultProvider()),
        ChangeNotifierProvider(create: (_) => SearchProvider()),
      ],
      child: MaterialApp(
        title: 'ShreyX Music',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const MainNavigation(),
      ),
    );
  }
}
