import 'package:dio/dio.dart';
import 'package:matrix/matrix.dart';

import '../domain/voice_error.dart';

/// Discovers the LiveKit SFU endpoint via .well-known and exchanges
/// a Matrix OpenID token for a LiveKit JWT.
class SfuDiscoveryService {
  SfuDiscoveryService({
    required Client client,
    Dio? dio,
  })  : _client = client,
        _dio = dio ?? Dio();

  final Client _client;
  final Dio _dio;

  /// Cached LiveKit service URL from .well-known discovery.
  String? _cachedLivekitServiceUrl;

  /// Discover the LiveKit SFU and obtain connection credentials.
  ///
  /// 1. Fetch .well-known/matrix/client for rtc_foci
  /// 2. Get an OpenID token from the homeserver
  /// 3. Exchange it for a LiveKit JWT at the lk-jwt-service
  Future<SfuCredentials> getCredentials({required String roomId}) async {
    final livekitServiceUrl = await _discoverLivekitServiceUrl();
    final jwt = await _exchangeForJwt(livekitServiceUrl, roomId);
    return jwt;
  }

  /// Step 1: Discover the LiveKit service URL from .well-known.
  Future<String> _discoverLivekitServiceUrl() async {
    if (_cachedLivekitServiceUrl != null) return _cachedLivekitServiceUrl!;

    final homeserver = _client.homeserver;
    if (homeserver == null) {
      throw const VoiceConfigError('No homeserver configured');
    }

    try {
      final response = await _dio.get(
        '$homeserver/.well-known/matrix/client',
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const VoiceConfigError(
          'Invalid .well-known response',
        );
      }

      // Try the stable key first, then the unstable MSC key
      final foci = data['org.matrix.msc4143.rtc_foci'] as List?;

      if (foci == null || foci.isEmpty) {
        throw const VoiceConfigError(
          'Homeserver does not support MatrixRTC voice. '
          'Missing org.matrix.msc4143.rtc_foci in .well-known/matrix/client. '
          'See https://docs.element.io/latest/element-server-suite-pro/configuring-components/configuring-matrix-rtc/',
        );
      }

      final firstFocus = foci.first;
      if (firstFocus is! Map || firstFocus['type'] != 'livekit') {
        throw const VoiceConfigError(
          'No LiveKit focus found in rtc_foci configuration',
        );
      }

      final url = firstFocus['livekit_service_url'] as String?;
      if (url == null || url.isEmpty) {
        throw const VoiceConfigError(
          'livekit_service_url is missing in rtc_foci',
        );
      }

      _cachedLivekitServiceUrl = url;
      return url;
    } on DioException catch (e) {
      throw VoiceConfigError(
        'Failed to fetch .well-known: ${e.message}',
      );
    }
  }

  /// Steps 2-3: Get OpenID token, exchange for LiveKit JWT.
  Future<SfuCredentials> _exchangeForJwt(
    String livekitServiceUrl,
    String roomId,
  ) async {
    // Step 2: Get an OpenID token from the homeserver
    final openIdToken = await _client.requestOpenIdToken(
      _client.userID!,
      {},
    );

    // Step 3: Exchange for LiveKit JWT at the lk-jwt-service
    // The lk-jwt-service endpoint is at /sfu/get under the base URL.
    // Strip trailing slash and append the path.
    final jwtUrl = livekitServiceUrl.endsWith('/')
        ? '${livekitServiceUrl}sfu/get'
        : '$livekitServiceUrl/sfu/get';

    try {
      final response = await _dio.post(
        jwtUrl,
        data: {
          'openid_token': {
            'access_token': openIdToken.accessToken,
            'token_type': openIdToken.tokenType,
            'matrix_server_name': openIdToken.matrixServerName,
            'expires_in': openIdToken.expiresIn,
          },
          'room': roomId,
          'device_id': _client.deviceID,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const VoiceConnectionError('Invalid JWT response from SFU auth');
      }

      final jwt = data['jwt'] as String?;
      final sfuUrl = data['url'] as String?;

      if (jwt == null || sfuUrl == null) {
        throw const VoiceConnectionError(
          'Missing jwt or url in SFU auth response',
        );
      }

      return SfuCredentials(jwt: jwt, sfuUrl: sfuUrl);
    } on DioException catch (e) {
      final responseBody = e.response?.data;
      throw VoiceConnectionError(
        'JWT exchange failed: ${responseBody ?? e.message}',
      );
    }
  }

  /// Clear cached discovery data (e.g., on logout).
  void clearCache() {
    _cachedLivekitServiceUrl = null;
  }
}

/// Credentials for connecting to a LiveKit SFU.
class SfuCredentials {
  const SfuCredentials({
    required this.jwt,
    required this.sfuUrl,
  });

  /// LiveKit JWT token for authentication.
  final String jwt;

  /// WebSocket URL for the LiveKit SFU.
  final String sfuUrl;
}
