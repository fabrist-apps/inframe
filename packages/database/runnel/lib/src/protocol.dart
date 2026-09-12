/// RESP version used for connection handshakes.
enum RedisProtocol {
  /// RESP2, negotiated explicitly with `HELLO 2`.
  resp2(2),

  /// RESP3, negotiated explicitly with `HELLO 3`.
  resp3(3);

  const RedisProtocol(this.version);

  /// Wire protocol version passed to `HELLO`.
  final int version;
}
