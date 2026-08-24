import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:dbus/dbus.dart';

typedef MediaCommand = Future<void> Function();

const _mprisService = 'org.mpris.MediaPlayer2.CloudAudiobook';
final _mprisPath = DBusObjectPath('/org/mpris/MediaPlayer2');
const _mprisRootInterface = 'org.mpris.MediaPlayer2';
const _mprisPlayerInterface = 'org.mpris.MediaPlayer2.Player';

class LinuxMpris {
  static final LinuxMpris _instance = LinuxMpris._();
  factory LinuxMpris() => _instance;
  LinuxMpris._();

  DBusClient? _client;
  _MprisPlayer? _player;

  Future<void> initialize({
    required MediaCommand onPlay,
    required MediaCommand onPause,
    required MediaCommand onNext,
    required MediaCommand onPrevious,
  }) async {
    if (!Platform.isLinux) return;
    try {
      final client = DBusClient.session();
      final reply = await client.requestName(_mprisService);
      if (reply != DBusRequestNameReply.primaryOwner &&
          reply != DBusRequestNameReply.alreadyOwner) {
        await client.close();
        return;
      }
      final player = _MprisPlayer(
        _mprisPath,
        onPlay: onPlay,
        onPause: onPause,
        onNext: onNext,
        onPrevious: onPrevious,
      );
      await client.registerObject(player);
      _client = client;
      _player = player;
    } catch (e) {
      developer.log('initialize error', name: 'MPRIS', error: e);
    }
  }

  Future<void> update({
    required String title,
    String artist = '',
    required bool playing,
    required Duration position,
    required Duration duration,
    required bool canGoNext,
    required bool canGoPrevious,
  }) async {
    final player = _player;
    if (player == null) return;
    player.update(
      title: title,
      artist: artist,
      playing: playing,
      position: position,
      duration: duration,
      canGoNext: canGoNext,
      canGoPrevious: canGoPrevious,
    );
    await player.emitPropertiesChanged(
      _mprisPlayerInterface,
      changedProperties: player.changedProperties(),
    );
  }

  Future<void> dispose() async {
    final client = _client;
    final player = _player;
    if (client != null && player != null) {
      await client.unregisterObject(player);
      await client.releaseName(_mprisService);
      await client.close();
    }
    _client = null;
    _player = null;
  }
}

class _MprisPlayer extends DBusObject {
  _MprisPlayer(
    super.path, {
    required this.onPlay,
    required this.onPause,
    required this.onNext,
    required this.onPrevious,
  });

  final MediaCommand onPlay;
  final MediaCommand onPause;
  final MediaCommand onNext;
  final MediaCommand onPrevious;

  String title = '';
  String artist = '';
  bool playing = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool canGoNext = false;
  bool canGoPrevious = false;

  void update({
    required String title,
    required String artist,
    required bool playing,
    required Duration position,
    required Duration duration,
    required bool canGoNext,
    required bool canGoPrevious,
  }) {
    this.title = title;
    this.artist = artist;
    this.playing = playing;
    this.position = position;
    this.duration = duration;
    this.canGoNext = canGoNext;
    this.canGoPrevious = canGoPrevious;
  }

  Map<String, DBusValue> changedProperties() => {
    'PlaybackStatus': DBusString(_playbackStatus),
    'Position': DBusInt64(position.inMicroseconds),
    'CanGoNext': DBusBoolean(canGoNext),
    'CanGoPrevious': DBusBoolean(canGoPrevious),
    'CanPlay': DBusBoolean(title.isNotEmpty),
    'CanPause': DBusBoolean(title.isNotEmpty),
    'CanSeek': DBusBoolean(false),
    'CanControl': DBusBoolean(true),
    'Metadata': _metadata,
  };

  String get _playbackStatus {
    if (title.isEmpty) return 'Stopped';
    return playing ? 'Playing' : 'Paused';
  }

  DBusDict get _metadata => DBusDict.stringVariant({
    'mpris:trackid': DBusObjectPath('/org/mpris/MediaPlayer2/Track/1'),
    'xesam:title': DBusString(title),
    'xesam:artist': DBusArray.string([artist]),
    'mpris:length': DBusInt64(duration.inMicroseconds),
  });

  Map<String, DBusValue> get _rootProperties => {
    'CanQuit': DBusBoolean(true),
    'CanRaise': DBusBoolean(true),
    'HasTrackList': DBusBoolean(false),
    'Identity': DBusString('云听书'),
    'DesktopEntry': DBusString('cloud-audiobook'),
    'SupportedUriSchemes': DBusArray.string([]),
    'SupportedMimeTypes': DBusArray.string([]),
  };

  Map<String, DBusValue> get _playerProperties => {
    'PlaybackStatus': DBusString(_playbackStatus),
    'Metadata': _metadata,
    'Position': DBusInt64(position.inMicroseconds),
    'CanGoNext': DBusBoolean(canGoNext),
    'CanGoPrevious': DBusBoolean(canGoPrevious),
    'CanPlay': DBusBoolean(title.isNotEmpty),
    'CanPause': DBusBoolean(title.isNotEmpty),
    'CanSeek': DBusBoolean(false),
    'CanControl': DBusBoolean(true),
  };

  @override
  List<DBusIntrospectInterface> introspect() => [
    DBusIntrospectInterface(
      _mprisRootInterface,
      properties: [
        DBusIntrospectProperty(
          'CanQuit',
          DBusSignature('b'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'CanRaise',
          DBusSignature('b'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'HasTrackList',
          DBusSignature('b'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'Identity',
          DBusSignature('s'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'DesktopEntry',
          DBusSignature('s'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'SupportedUriSchemes',
          DBusSignature('as'),
          access: DBusPropertyAccess.read,
        ),
        DBusIntrospectProperty(
          'SupportedMimeTypes',
          DBusSignature('as'),
          access: DBusPropertyAccess.read,
        ),
      ],
    ),
    DBusIntrospectInterface(
      _mprisPlayerInterface,
      methods: [
        for (final name in ['Play', 'Pause', 'PlayPause', 'Next', 'Previous'])
          DBusIntrospectMethod(name),
      ],
      properties: [
        for (final property in {
          'PlaybackStatus': 's',
          'Metadata': 'a{sv}',
          'Position': 'x',
          'CanGoNext': 'b',
          'CanGoPrevious': 'b',
          'CanPlay': 'b',
          'CanPause': 'b',
          'CanSeek': 'b',
          'CanControl': 'b',
        }.entries)
          DBusIntrospectProperty(
            property.key,
            DBusSignature(property.value),
            access: DBusPropertyAccess.read,
          ),
      ],
    ),
  ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != _mprisPlayerInterface) {
      return DBusMethodSuccessResponse();
    }
    switch (call.name) {
      case 'Play':
        await onPlay();
      case 'Pause':
        await onPause();
      case 'PlayPause':
        await (playing ? onPause() : onPlay());
      case 'Next':
        await onNext();
      case 'Previous':
        await onPrevious();
    }
    return DBusMethodSuccessResponse();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface == _mprisRootInterface) {
      final value = _rootProperties[name];
      if (value != null) return DBusGetPropertyResponse(value);
    }
    if (interface == _mprisPlayerInterface) {
      final value = _playerProperties[name];
      if (value != null) return DBusGetPropertyResponse(value);
    }
    return DBusGetPropertyResponse(DBusString(''));
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    return DBusGetAllPropertiesResponse(switch (interface) {
      _mprisRootInterface => _rootProperties,
      _mprisPlayerInterface => _playerProperties,
      _ => const {},
    });
  }
}
