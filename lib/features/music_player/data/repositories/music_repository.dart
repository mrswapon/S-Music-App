import 'package:on_audio_query/on_audio_query.dart' hide SongModel;
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/song.dart';
import '../models/song_model.dart';

class MusicRepository {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  Future<List<Song>> getLocalSongs() async {
    final hasPermission = await _requestPermission();
    if (!hasPermission) return [];

    final songs = await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    return songs
        .where((song) => song.isMusic == true || song.fileExtension == 'mp3')
        .map(
          (song) => SongModel.fromDeviceAudio(
            id: song.id,
            title: song.title,
            artist: song.artist ?? 'Unknown Artist',
            album: song.album,
            durationMs: song.duration,
            data: song.data,
          ),
        )
        .toList();
  }

  List<Song> getOnlineSongs() {
    return AppConstants.sampleSongs
        .asMap()
        .entries
        .map((entry) => SongModel.fromOnlineMap(
              entry.value,
              10000 + entry.key,
            ))
        .toList();
  }

  Future<List<Song>> getAllSongs() async {
    final localSongs = await getLocalSongs();
    final onlineSongs = getOnlineSongs();
    return [...localSongs, ...onlineSongs];
  }

  Future<bool> _requestPermission() async {
    PermissionStatus status;

    // Android 13+ uses granular media permissions
    if (await Permission.audio.status.isDenied) {
      status = await Permission.audio.request();
      if (status.isGranted) return true;
    }

    if (await Permission.audio.status.isGranted) return true;

    // Fallback for older Android versions
    if (await Permission.storage.status.isDenied) {
      status = await Permission.storage.request();
      if (status.isGranted) return true;
    }

    if (await Permission.storage.status.isGranted) return true;

    return false;
  }
}
