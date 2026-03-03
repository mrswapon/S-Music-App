# S Music

A modern music player built with Flutter using **Clean Architecture** and **BLoC** state management. Streams trending and viral music from YouTube with audio-only playback, and scans local device files.

## Features

- Fetches daily trending and viral music from YouTube
- Audio-only streaming (no video download)
- Local device music scanning
- Mini player with progress bar
- Full-screen Now Playing with seek bar and album art
- Shuffle and repeat modes (off / all / one)
- Dark and light theme toggle
- Animated UI (bounce taps, pulsing indicators, slide-fade entries)

## Project Structure

```
lib/
├── main.dart                              # App entry, MultiBlocProvider setup
│
├── core/
│   ├── constants/
│   │   └── app_constants.dart             # App name, sample song URLs
│   ├── theme/
│   │   └── app_theme.dart                 # Light/dark theme (#BB63E0 primary)
│   ├── utils/
│   │   └── format_utils.dart              # Duration (MM:SS) and view count (1.5M) formatting
│   └── widgets/
│       ├── animated_icon_btn.dart          # Icon button with scale-bounce on tap
│       ├── bounce_tap.dart                 # Wrapper that scales down on press
│       ├── pulse_widget.dart               # Continuous pulsing animation
│       ├── slide_fade_widget.dart          # Staggered slide-up + fade-in entry
│       └── spin_button.dart                # 360° rotation on tap
│
└── features/
    └── music_player/
        │
        ├── data/
        │   ├── models/
        │   │   └── song_model.dart         # SongModel with factory constructors:
        │   │                                #   fromOnlineMap, fromDeviceAudio, fromYouTube
        │   └── repositories/
        │       ├── music_repository.dart    # Local + online song fetching, permissions
        │       ├── youtube_repository.dart  # YouTube search, manifest fetch, stream selection
        │       └── audio_stream_server.dart # Localhost HTTP proxy for YouTube audio
        │
        ├── domain/
        │   └── entities/
        │       └── song.dart               # Song entity (id, title, artist, path, videoId, etc.)
        │
        └── presentation/
            ├── bloc/
            │   ├── music_player_bloc.dart   # Playback control, 3-strategy YouTube streaming
            │   ├── music_player_event.dart  # Play, Pause, Seek, Next, Prev, Shuffle, Repeat
            │   ├── music_player_state.dart  # PlayerStatus, position, duration, repeat mode
            │   ├── youtube_cubit.dart       # Trending/viral song list fetching
            │   └── theme_cubit.dart         # Dark/light theme toggle
            ├── screens/
            │   ├── home_screen.dart         # 3-tab layout: Trending, Viral, My Music
            │   └── now_playing_screen.dart  # Full-screen player with album art and controls
            └── widgets/
                ├── song_tile.dart           # Song card with thumbnail, metadata, play button
                ├── mini_player.dart         # Persistent bottom bar with playback controls
                └── shimmer_list.dart        # Loading skeleton placeholder
```

## Architecture

Clean Architecture with three layers:

```
┌──────────────────────────────────────────────────┐
│  PRESENTATION                                    │
│  Screens, Widgets, BLoC/Cubit                    │
│  (home_screen, now_playing, mini_player,         │
│   MusicPlayerBloc, YouTubeCubit, ThemeCubit)     │
├──────────────────────────────────────────────────┤
│  DOMAIN                                          │
│  Entities                                        │
│  (Song)                                          │
├──────────────────────────────────────────────────┤
│  DATA                                            │
│  Models, Repositories                            │
│  (SongModel, MusicRepository, YouTubeRepository, │
│   AudioStreamServer)                             │
├──────────────────────────────────────────────────┤
│  EXTERNAL                                        │
│  just_audio, youtube_explode_dart, on_audio_query│
└──────────────────────────────────────────────────┘
```

## State Management

| BLoC / Cubit | Responsibility |
|---|---|
| `MusicPlayerBloc` | Audio playback lifecycle, playlist, shuffle, repeat, seek, YouTube stream resolution |
| `YouTubeCubit` | Fetches trending and viral song lists from YouTube (parallel loading) |
| `ThemeCubit` | Toggles dark/light theme |

## YouTube Playback Strategy

When a user taps a YouTube song, the app tries three strategies in order:

1. **Direct CDN URL** — Passes the YouTube stream URL directly to ExoPlayer (fastest)
2. **Localhost Proxy** — Routes audio through a local HTTP server using youtube_explode's authenticated client (handles 403s)
3. **Fresh Client + Headers** — Refreshes the YouTube client session and retries with browser-like headers

## Dependencies

| Package | Purpose |
|---|---|
| `flutter_bloc` | BLoC state management |
| `equatable` | Value equality for states/entities |
| `just_audio` | Audio playback (ExoPlayer on Android) |
| `youtube_explode_dart` | YouTube search and audio stream extraction |
| `on_audio_query` | Local device audio file scanning |
| `permission_handler` | Runtime permission requests |
| `shimmer` | Loading skeleton animations |

## Getting Started

```bash
flutter pub get
flutter run
```

### Run Tests

```bash
flutter test
```

## Android Permissions

| Permission | Purpose |
|---|---|
| `INTERNET` | YouTube streaming |
| `READ_MEDIA_AUDIO` | Local music (Android 13+) |
| `READ_EXTERNAL_STORAGE` | Local music (older Android) |

`usesCleartextTraffic` is enabled for the localhost audio proxy server.
