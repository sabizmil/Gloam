import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

/// Pure-Dart crypto implementations for macOS desktop (and all platforms).
///
/// Replaces the SDK's default FFI-based PBKDF2 (which needs libcrypto.1.1.dylib)
/// with the `cryptography` package's pure Dart implementation.
/// Slightly slower (~50ms) but eliminates the OpenSSL native dependency entirely.
class GloamNativeImplementations extends NativeImplementations {
  const GloamNativeImplementations();

  @override
  Future<Uint8List> keyFromPassphrase(
    KeyFromPassphraseArgs args, {
    bool retryInDummy = true,
  }) async {
    final info = args.info;

    if (info.algorithm != AlgorithmTypes.pbkdf2) {
      throw Exception('Unknown passphrase algorithm: ${info.algorithm}');
    }
    if (info.iterations == null || info.salt == null) {
      throw Exception('Passphrase info missing iterations or salt');
    }

    final bits = info.bits ?? 256;

    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha512(),
      iterations: info.iterations!,
      bits: bits,
    );

    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(args.passphrase)),
      nonce: utf8.encode(info.salt!),
    );

    return Uint8List.fromList(await secretKey.extractBytes());
  }

  @override
  Future<RoomKeys> generateUploadKeys(
    GenerateUploadKeysArgs args, {
    bool retryInDummy = true,
  }) {
    // Fall back to the default dummy (same-thread) implementation
    return NativeImplementations.dummy.generateUploadKeys(args);
  }

  @override
  Future<Uint8List?> decryptFile(
    EncryptedFile file, {
    bool retryInDummy = true,
  }) {
    return NativeImplementations.dummy.decryptFile(file);
  }

  @override
  MatrixImageFileResizedResponse? shrinkImage(
    MatrixImageFileResizeArguments args, {
    bool retryInDummy = false,
  }) {
    return NativeImplementations.dummy.shrinkImage(args);
  }

  @override
  MatrixImageFileResizedResponse? calcImageMetadata(
    Uint8List bytes, {
    bool retryInDummy = false,
  }) {
    return NativeImplementations.dummy.calcImageMetadata(bytes);
  }
}
