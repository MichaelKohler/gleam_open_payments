/// Errors that can occur while using the Open Payments SDK. Every public
/// function that talks to a server or reads key material returns
/// `Result(_, OpenPaymentsError)`, so callers can match on the failure kind
/// instead of parsing a message.
pub type OpenPaymentsError {
  /// The request could not be sent: the URL was invalid, the request could
  /// not be signed, or the underlying HTTP client failed to reach the
  /// server.
  TransportError(String)
  /// The server responded, but with a non-success status. `body` is the raw
  /// response body, which often carries a machine-readable error from the
  /// auth or resource server.
  ApiError(status: Int, body: String)
  /// The response body was not valid JSON, or didn't match the shape
  /// expected for this operation.
  DecodeError(String)
  /// The private key file could not be read, or didn't contain a valid
  /// PKCS#8 PEM-encoded Ed25519 private key.
  KeyError(String)
}
