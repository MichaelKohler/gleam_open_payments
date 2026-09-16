import gleam/dynamic/decode
import gleam/http
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import gleam/result
import open_payments/client.{type Client}
import open_payments/request
import open_payments/types.{
  type Access, type AccessTokenResponse, type Key, decode_access_token_response,
  encode_access, optional_field,
}

pub type Finish {
  Finish(method: String, uri: String, nonce: String)
}

pub type Interact {
  Interact(start: List(String), finish: Option(Finish))
}

pub type GrantOptions {
  GrantOptions(
    auth_server_url: String,
    access: Access,
    interact: Option(Interact),
    address: String,
  )
}

pub type AccessTokenBodyProperty {
  AccessTokenBodyProperty(access: Access)
}

pub type ClientType {
  ClientDirectedIdentity(jwk: Key)
  ClientWalletAddressObject(wallet_address: String)
}

pub type Body {
  Body(
    access_token: AccessTokenBodyProperty,
    client: ClientType,
    interact: Option(Interact),
  )
}

pub type InteractResponse {
  InteractResponse(redirect: String, finish: Option(String))
}

pub type ContinueAccessToken {
  ContinueAccessToken(value: String)
}

pub type ContinueResponse {
  ContinueResponse(
    access_token: ContinueAccessToken,
    uri: String,
    wait: Option(Int),
  )
}

/// The result of a grant request. A grant is either pending client
/// interaction (`PendingGrant`) or has already been approved (`Grant`).
/// See https://openpayments.dev/apis/auth-server/operations/post-request/
pub type GrantResponse {
  PendingGrant(interact: InteractResponse, continue: ContinueResponse)
  Grant(access_token: AccessTokenResponse, continue: ContinueResponse)
}

@internal
pub fn encode_finish(finish: Finish) -> Json {
  json.object([
    #("method", json.string(finish.method)),
    #("uri", json.string(finish.uri)),
    #("nonce", json.string(finish.nonce)),
  ])
}

@internal
pub fn encode_interact(interact: Interact) -> Json {
  [#("start", json.array(interact.start, json.string))]
  |> optional_field("finish", interact.finish, encode_finish)
  |> json.object
}

@internal
pub fn encode_access_token(access_token: AccessTokenBodyProperty) -> Json {
  json.object([#("access", json.array([access_token.access], encode_access))])
}

@internal
pub fn encode_key(key: Key) -> Json {
  json.object([
    #("kid", json.string(key.kid)),
    #("x", json.string(key.x)),
    #("alg", json.string(key.alg)),
    #("kty", json.string(key.kty)),
    #("crv", json.string(key.crv)),
  ])
}

@internal
pub fn encode_client(client: ClientType) -> Json {
  case client {
    ClientDirectedIdentity(jwk) -> encode_key(jwk)
    ClientWalletAddressObject(wallet_address) -> json.string(wallet_address)
  }
}

@internal
pub fn encode_body(body: Body) -> Json {
  [
    #("access_token", encode_access_token(body.access_token)),
    #("client", encode_client(body.client)),
  ]
  |> optional_field("interact", body.interact, encode_interact)
  |> json.object
}

@internal
pub fn decode_interact_response() -> decode.Decoder(InteractResponse) {
  use redirect <- decode.field("redirect", decode.string)
  use finish <- decode.optional_field(
    "finish",
    None,
    decode.string |> decode.map(Some),
  )
  decode.success(InteractResponse(redirect: redirect, finish: finish))
}

@internal
pub fn decode_continue_access_token() -> decode.Decoder(ContinueAccessToken) {
  use value <- decode.field("value", decode.string)
  decode.success(ContinueAccessToken(value: value))
}

@internal
pub fn decode_continue_response() -> decode.Decoder(ContinueResponse) {
  use access_token <- decode.field(
    "access_token",
    decode_continue_access_token(),
  )
  use uri <- decode.field("uri", decode.string)
  use wait <- decode.optional_field(
    "wait",
    None,
    decode.int |> decode.map(Some),
  )
  decode.success(ContinueResponse(
    access_token: access_token,
    uri: uri,
    wait: wait,
  ))
}

@internal
pub fn decode_pending_grant() -> decode.Decoder(GrantResponse) {
  use interact <- decode.field("interact", decode_interact_response())
  use continue <- decode.field("continue", decode_continue_response())
  decode.success(PendingGrant(interact: interact, continue: continue))
}

@internal
pub fn decode_grant() -> decode.Decoder(GrantResponse) {
  use access_token <- decode.field(
    "access_token",
    decode_access_token_response(),
  )
  use continue <- decode.field("continue", decode_continue_response())
  decode.success(Grant(access_token: access_token, continue: continue))
}

@internal
pub fn decode_grant_response() -> decode.Decoder(GrantResponse) {
  decode.one_of(decode_pending_grant(), or: [decode_grant()])
}

pub fn request(
  client: Client,
  options: GrantOptions,
) -> Result(GrantResponse, String) {
  let url = options.auth_server_url
  let body =
    Body(
      access_token: AccessTokenBodyProperty(options.access),
      client: ClientWalletAddressObject(client.wallet_address_url),
      interact: options.interact,
    )
    |> encode_body

  use response_body <- result.try(request.send_request(
    client,
    url,
    http.Post,
    Some(body),
    token: None,
  ))

  json.parse(response_body, decode_grant_response())
  |> result.map_error(fn(_) { "Failed to parse grant response" })
}

/// Returns `True` if the grant requires the user to complete an interaction
/// (e.g. redirecting to the auth server) before it can be used.
pub fn is_interactive_grant(grant: GrantResponse) -> Bool {
  case grant {
    PendingGrant(..) -> True
    Grant(..) -> False
  }
}

pub type ContinuationResponse {
  ContinuationResponse(
    access_token: Option(AccessTokenResponse),
    continue: ContinueResponse,
  )
}

@internal
pub fn encode_continue_body(interact_ref: String) -> Json {
  json.object([#("interact_ref", json.string(interact_ref))])
}

@internal
pub fn decode_continuation_response() -> decode.Decoder(ContinuationResponse) {
  use access_token <- decode.optional_field(
    "access_token",
    None,
    decode_access_token_response() |> decode.map(Some),
  )
  use continue <- decode.field("continue", decode_continue_response())
  decode.success(ContinuationResponse(
    access_token: access_token,
    continue: continue,
  ))
}

/// Continues a pending grant after the user has completed interaction.
/// See https://openpayments.dev/apis/auth-server/operations/post-continue/
pub fn continue(
  client: Client,
  response: ContinueResponse,
  interact_ref: String,
) -> Result(ContinuationResponse, String) {
  let body = encode_continue_body(interact_ref)

  use response_body <- result.try(request.send_request(
    client,
    response.uri,
    http.Post,
    Some(body),
    token: Some(response.access_token.value),
  ))

  json.parse(response_body, decode_continuation_response())
  |> result.map_error(fn(_) { "Failed to parse continuation response" })
}

/// Cancels a pending grant request, invalidating its continuation so it can
/// no longer be used to continue or retrieve the grant.
/// See https://openpayments.dev/apis/auth-server/operations/delete-continue/
pub fn cancel(
  client: Client,
  response: ContinueResponse,
) -> Result(Nil, String) {
  use _ <- result.try(request.send_request(
    client,
    response.uri,
    http.Delete,
    None,
    token: Some(response.access_token.value),
  ))

  Ok(Nil)
}
