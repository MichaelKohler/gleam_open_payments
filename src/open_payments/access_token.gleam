import gleam/dynamic/decode
import gleam/http
import gleam/option.{None, Some}
import gleam/result
import open_payments/client.{type Client}
import open_payments/request
import open_payments/types.{
  type AccessTokenResponse, decode_access_token_response,
}

/// Decodes the `access_token` field of a token rotation response.
@internal
pub fn decode_rotate_response() -> decode.Decoder(AccessTokenResponse) {
  use access_token <- decode.field(
    "access_token",
    decode_access_token_response(),
  )
  decode.success(access_token)
}

/// Rotates an access token, exchanging it for a new token value while
/// keeping the same grant. The token's `manage` URL is used as the request
/// URL.
/// See https://openpayments.dev/apis/auth-server/operations/post-token/
pub fn rotate(
  client: Client,
  access_token: AccessTokenResponse,
) -> Result(AccessTokenResponse, String) {
  request.send_and_decode(
    client,
    access_token.manage,
    http.Post,
    None,
    token: Some(access_token.value),
    decoder: decode_rotate_response(),
    error_context: "Failed to parse access token response",
  )
}

/// Revokes an access token, invalidating it immediately. The token's
/// `manage` URL is used as the request URL.
/// See https://openpayments.dev/apis/auth-server/operations/delete-token/
pub fn revoke(
  client: Client,
  access_token: AccessTokenResponse,
) -> Result(Nil, String) {
  request.send_request(
    client,
    access_token.manage,
    http.Delete,
    None,
    token: Some(access_token.value),
  )
  |> result.replace(Nil)
}
