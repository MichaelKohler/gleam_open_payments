import gleam/dynamic/decode
import gleam/http
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import gleam/result
import open_payments/client.{type Client}
import open_payments/error.{type OpenPaymentsError, ValidationError}
import open_payments/request
import open_payments/types.{
  type Access, type AccessTokenResponse, type Key, decode_access_token_response,
  encode_access, optional_field,
}

/// How the client is notified once the user has completed interaction with
/// the auth server, as requested in a grant's `interact` options.
pub type Finish {
  Finish(method: String, uri: String, nonce: String)
}

/// The interaction methods to request for a grant, and optionally how the
/// client should be notified when interaction finishes.
pub type Interact {
  Interact(start: List(String), finish: Option(Finish))
}

/// How the client making the grant request identifies itself: either
/// directly with its public key (`jwk`), or via a wallet address whose keys
/// the auth server can look up.
pub type ClientType {
  /// Sent as `{"jwk": ...}`. Only usable for non-interactive grants.
  ClientDirectedIdentity(jwk: Key)
  /// Sent as `{"walletAddress": ...}`.
  ClientWalletAddressObject(wallet_address: String)
  /// Sent as a bare wallet address string. Deprecated by the Open Payments
  /// spec in favour of `ClientWalletAddressObject`; only use it for auth
  /// servers that don't yet accept the object form.
  ClientWalletAddressString(wallet_address: String)
}

/// Currently the Open Payments spec only defines `"uri"`.
pub type SubjectIdFormat {
  SubjectIdFormatUri
}

/// A single identifier for the subject the client is requesting
/// information about.
pub type SubjectId {
  SubjectId(id: String, format: SubjectIdFormat)
}

/// The subject information returned on the continuation response once
/// interaction completes. A grant request names its subject with a single
/// `SubjectId` instead (see `GrantOptions`).
pub type Subject {
  Subject(sub_ids: List(SubjectId))
}

/// The options for a grant request. `access` may list more than one access
/// kind (e.g. incoming-payment and quote) to request them all in a single
/// grant, or be left as `[]` for a subject-only request. `client_type`
/// defaults to identifying the client by its own wallet address
/// (`ClientWalletAddressObject`, sent as `{"walletAddress": ...}`) when
/// left as `None`; pass
/// `Some(ClientDirectedIdentity(key))` to identify the client by its public
/// key instead, which is only allowed without `interact`: `request` returns
/// a `ValidationError` otherwise. `subject` requests information about a subject (e.g. to
/// confirm wallet address ownership) rather than, or alongside, an access
/// token. It is sent as the single `sub_ids` entry the spec allows, and
/// requires `interact` to be set: `request` returns a `ValidationError`
/// otherwise.
/// See https://openpayments.dev/apis/auth-server/operations/post-request/
pub type GrantOptions {
  GrantOptions(
    auth_server_url: String,
    access: List(Access),
    interact: Option(Interact),
    address: String,
    client_type: Option(ClientType),
    subject: Option(SubjectId),
  )
}

/// Wraps the `access` requested for the token issued by a grant.
pub type AccessTokenBodyProperty {
  AccessTokenBodyProperty(access: List(Access))
}

/// The request body sent to the auth server to request a grant.
pub type Body {
  Body(
    access_token: Option(AccessTokenBodyProperty),
    client: ClientType,
    interact: Option(Interact),
    subject: Option(SubjectId),
  )
}

/// Where to redirect the user to interact with the auth server, and how the
/// client will be notified once interaction finishes.
pub type InteractResponse {
  InteractResponse(redirect: String, finish: Option(String))
}

/// The access token used to continue a pending grant.
pub type ContinueAccessToken {
  ContinueAccessToken(value: String)
}

/// Where and how to continue a grant, and how long to wait before polling
/// again.
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
  json.object([#("access", json.array(access_token.access, encode_access))])
}

@internal
pub fn encode_subject_id_format(format: SubjectIdFormat) -> Json {
  json.string(case format {
    SubjectIdFormatUri -> "uri"
  })
}

@internal
pub fn encode_subject_id(subject_id: SubjectId) -> Json {
  json.object([
    #("id", json.string(subject_id.id)),
    #("format", encode_subject_id_format(subject_id.format)),
  ])
}

@internal
pub fn encode_subject(subject: SubjectId) -> Json {
  json.object([#("sub_ids", json.array([subject], encode_subject_id))])
}

@internal
pub fn encode_key(key: Key) -> Json {
  json.object([
    #("kid", json.string(key.kid)),
    #("x", json.string(key.x)),
    #("alg", json.string(key.alg)),
    #("kty", json.string(key.kty)),
    #("crv", json.string(key.crv)),
    #("use", json.string(key.use_)),
  ])
}

@internal
pub fn encode_client(client: ClientType) -> Json {
  case client {
    ClientDirectedIdentity(jwk) -> json.object([#("jwk", encode_key(jwk))])
    ClientWalletAddressObject(wallet_address) ->
      json.object([#("walletAddress", json.string(wallet_address))])
    ClientWalletAddressString(wallet_address) -> json.string(wallet_address)
  }
}

@internal
pub fn encode_body(body: Body) -> Json {
  [#("client", encode_client(body.client))]
  |> optional_field("access_token", body.access_token, encode_access_token)
  |> optional_field("interact", body.interact, encode_interact)
  |> optional_field("subject", body.subject, encode_subject)
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

/// Requests a grant from the auth server for the given access. Pass more
/// than one `Access` in `options.access` to request them all under a single
/// grant, rather than requesting each with its own grant. Leave `access` as
/// `[]` for a subject-only request (see `options.subject`).
/// See https://openpayments.dev/apis/auth-server/operations/post-request/
pub fn request(
  client: Client,
  options: GrantOptions,
) -> Result(GrantResponse, OpenPaymentsError) {
  use Nil <- result.try(validate_options(options))
  let url = options.auth_server_url
  let client_type = case options.client_type {
    Some(client_type) -> client_type
    None -> ClientWalletAddressObject(client.wallet_address_url)
  }
  let access_token = case options.access {
    [] -> None
    access -> Some(AccessTokenBodyProperty(access))
  }
  let body =
    Body(
      access_token: access_token,
      client: client_type,
      interact: options.interact,
      subject: options.subject,
    )
    |> encode_body

  request.send_and_decode(
    client,
    url,
    http.Post,
    Some(body),
    token: None,
    decoder: decode_grant_response(),
    error_context: "Failed to parse grant response",
  )
}

/// Rejects option combinations the Open Payments spec forbids, before
/// anything is sent.
fn validate_options(options: GrantOptions) -> Result(Nil, OpenPaymentsError) {
  case options.client_type, options.interact, options.subject {
    Some(ClientDirectedIdentity(_)), Some(_), _ ->
      Error(ValidationError(
        "A directed identity (jwk) client can only be used for non-interactive grants",
      ))
    _, None, Some(_) ->
      Error(ValidationError("A grant request with a subject requires interact"))
    _, _, _ -> Ok(Nil)
  }
}

/// Returns `True` if the grant requires the user to complete an interaction
/// before it can be used.
pub fn is_interactive_grant(grant: GrantResponse) -> Bool {
  case grant {
    PendingGrant(..) -> True
    Grant(..) -> False
  }
}

/// The result of continuing a pending grant. `access_token` is present once
/// the grant has been approved; `subject` is present once the requested
/// subject information has been provided.
pub type ContinuationResponse {
  ContinuationResponse(
    access_token: Option(AccessTokenResponse),
    subject: Option(Subject),
    continue: ContinueResponse,
  )
}

@internal
pub fn encode_continue_body(interact_ref: String) -> Json {
  json.object([#("interact_ref", json.string(interact_ref))])
}

@internal
pub fn decode_subject_id_format() -> decode.Decoder(SubjectIdFormat) {
  use format <- decode.then(decode.string)
  case format {
    "uri" -> decode.success(SubjectIdFormatUri)
    _ -> decode.failure(SubjectIdFormatUri, "SubjectIdFormat")
  }
}

@internal
pub fn decode_subject_id() -> decode.Decoder(SubjectId) {
  use id <- decode.field("id", decode.string)
  use format <- decode.field("format", decode_subject_id_format())
  decode.success(SubjectId(id: id, format: format))
}

@internal
pub fn decode_subject() -> decode.Decoder(Subject) {
  use sub_ids <- decode.field("sub_ids", decode.list(decode_subject_id()))
  decode.success(Subject(sub_ids: sub_ids))
}

@internal
pub fn decode_continuation_response() -> decode.Decoder(ContinuationResponse) {
  use access_token <- decode.optional_field(
    "access_token",
    None,
    decode_access_token_response() |> decode.map(Some),
  )
  use subject <- decode.optional_field(
    "subject",
    None,
    decode_subject() |> decode.map(Some),
  )
  use continue <- decode.field("continue", decode_continue_response())
  decode.success(ContinuationResponse(
    access_token: access_token,
    subject: subject,
    continue: continue,
  ))
}

/// Continues a pending grant. Pass the `interact_ref` received once the user
/// has completed interaction, or `None` to poll the grant (e.g. after the
/// `wait` period), in which case the request is sent without a body.
/// See https://openpayments.dev/apis/auth-server/operations/post-continue/
pub fn continue(
  client: Client,
  response: ContinueResponse,
  interact_ref: Option(String),
) -> Result(ContinuationResponse, OpenPaymentsError) {
  let body = option.map(interact_ref, encode_continue_body)

  request.send_and_decode(
    client,
    response.uri,
    http.Post,
    body,
    token: Some(response.access_token.value),
    decoder: decode_continuation_response(),
    error_context: "Failed to parse continuation response",
  )
}

/// Cancels a pending grant request, invalidating its continuation so it can
/// no longer be used to continue or retrieve the grant.
/// See https://openpayments.dev/apis/auth-server/operations/delete-continue/
pub fn cancel(
  client: Client,
  response: ContinueResponse,
) -> Result(Nil, OpenPaymentsError) {
  request.send_request(
    client,
    response.uri,
    http.Delete,
    None,
    token: Some(response.access_token.value),
  )
  |> result.replace(Nil)
}
