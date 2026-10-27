import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

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
  /// response body. `error` is the machine-readable error parsed from it,
  /// when the body carries one. `as_uri` is the auth server named in a
  /// `WWW-Authenticate: GNAP as_uri=...` header, which resource servers send
  /// on a 401 to say where an access token can be requested.
  ApiError(
    status: Int,
    body: String,
    error: Option(ServerError),
    as_uri: Option(String),
  )
  /// The response body was not valid JSON, or didn't match the shape
  /// expected for this operation.
  DecodeError(String)
  /// The private key file could not be read, or didn't contain a valid
  /// PKCS#8 PEM-encoded Ed25519 private key.
  KeyError(String)
}

/// The `error` object returned in the body of a failed request.
/// See https://openpayments.dev/apis/auth-server/operations/post-request/
/// and https://openpayments.dev/apis/resource-server/operations/create-incoming-payment/
pub type ServerError {
  ServerError(
    code: ErrorCode,
    description: Option(String),
    details: Option(Dynamic),
  )
}

/// The error codes defined by the Open Payments auth server. Codes not in
/// this list, such as the free-form codes returned by resource servers, are
/// kept as `OtherErrorCode`.
pub type ErrorCode {
  /// The client is unknown to the auth server, or its signature could not be
  /// verified.
  InvalidClient
  /// The request was missing a required parameter or was otherwise
  /// malformed.
  InvalidRequest
  /// The request was denied, e.g. because the user rejected the grant.
  RequestDenied
  /// The client polled a continuation before its `wait` period elapsed and
  /// should back off before trying again.
  TooFast
  /// The continuation URI or access token is invalid, or the grant can no
  /// longer be continued.
  InvalidContinuation
  /// The access token could not be rotated.
  InvalidRotation
  OtherErrorCode(String)
}

@internal
pub fn decode_error_code() -> decode.Decoder(ErrorCode) {
  use code <- decode.then(decode.string)
  decode.success(case code {
    "invalid_client" -> InvalidClient
    "invalid_request" -> InvalidRequest
    "request_denied" -> RequestDenied
    "too_fast" -> TooFast
    "invalid_continuation" -> InvalidContinuation
    "invalid_rotation" -> InvalidRotation
    other -> OtherErrorCode(other)
  })
}

/// Decodes a `{"error": ...}` body. GNAP allows `error` to be either an
/// object with a `code`, or just the code as a string.
@internal
pub fn decode_server_error() -> decode.Decoder(ServerError) {
  let object = {
    use code <- decode.field("code", decode_error_code())
    use description <- decode.optional_field(
      "description",
      None,
      decode.string |> decode.map(Some),
    )
    use details <- decode.optional_field(
      "details",
      None,
      decode.dynamic |> decode.map(Some),
    )
    decode.success(ServerError(
      code: code,
      description: description,
      details: details,
    ))
  }
  let code_only =
    decode_error_code()
    |> decode.map(ServerError(code: _, description: None, details: None))

  use error <- decode.field("error", decode.one_of(object, or: [code_only]))
  decode.success(error)
}

/// Extracts `as_uri` from a `WWW-Authenticate` header value such as
/// `GNAP as_uri="https://auth.example/"`. Returns `None` for other schemes
/// or when the parameter is missing.
@internal
pub fn parse_as_uri(www_authenticate: String) -> Option(String) {
  let header = string.trim(www_authenticate)
  case string.split_once(header, " ") {
    Ok(#(scheme, params)) ->
      case string.lowercase(scheme) {
        "gnap" ->
          params
          |> string.split(",")
          |> list.find_map(fn(param) {
            case string.split_once(string.trim(param), "=") {
              Ok(#(name, value)) ->
                case string.lowercase(string.trim(name)) {
                  "as_uri" -> Ok(unquote(string.trim(value)))
                  _ -> Error(Nil)
                }
              Error(Nil) -> Error(Nil)
            }
          })
          |> option.from_result
        _ -> None
      }
    Error(Nil) -> None
  }
}

fn unquote(value: String) -> String {
  case string.starts_with(value, "\"") && string.ends_with(value, "\"") {
    True ->
      value
      |> string.drop_start(1)
      |> string.drop_end(1)
    False -> value
  }
}

@internal
pub fn from_response(
  status status: Int,
  body body: String,
  www_authenticate www_authenticate: Result(String, Nil),
) -> OpenPaymentsError {
  let error =
    json.parse(body, decode_server_error())
    |> option.from_result
  let as_uri =
    www_authenticate
    |> result.map(parse_as_uri)
    |> result.unwrap(None)

  ApiError(status: status, body: body, error: error, as_uri: as_uri)
}
