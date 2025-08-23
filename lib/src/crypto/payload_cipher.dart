/// Abstraction for encrypting and decrypting job payloads at rest.
abstract class PayloadCipher {
  const PayloadCipher();

  bool get isEnabled;

  Map<String, dynamic> encryptPayload(Map<String, dynamic> plaintext);

  Map<String, dynamic> decryptPayload(Map<String, dynamic> ciphertext);
}

/// No-op cipher used by default when encryption is not configured.
class NoopCipher extends PayloadCipher {
  const NoopCipher();

  @override
  bool get isEnabled => false;

  @override
  Map<String, dynamic> decryptPayload(Map<String, dynamic> ciphertext) =>
      ciphertext;

  @override
  Map<String, dynamic> encryptPayload(Map<String, dynamic> plaintext) =>
      plaintext;
}
