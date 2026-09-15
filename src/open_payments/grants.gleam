import gleam/dynamic/decode
import gleam/http
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import gleam/result
import open_payments/client.{type Client}
import open_payments/request
import open_payments/types.{type Key}

pub type IncomingAction {
  IncomingCreate
  IncomingComplete
  IncomingRead
  IncomingReadAll
  IncomingList
  IncomingListAll
}

pub type OutgoingAction {
  OutgoingCreate
  OutgoingRead
  OutgoingReadAll
  OutgoingList
  OutgoingListAll
}

pub type QuoteAction {
  QuoteCreate
  QuoteRead
  QuoteReadAll
}

pub type Amount {
  Amount(value: Int, asset_code: String, asset_scale: Int)
}

pub type LimitAmount {
  NoAmount
  DebitAmount(Amount)
  ReceiveAmount(Amount)
}

pub type Limits {
  Limits(
    receiver: Option(String),
    interval: Option(String),
    amount: LimitAmount,
  )
}

pub type Access {
  AccessIncoming(actions: List(IncomingAction), identifier: Option(String))
  AccessOutgoing(
    actions: List(OutgoingAction),
    identifier: String,
    limits: Option(Limits),
  )
  AccessQuote(actions: List(QuoteAction))
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
    interact: Interact,
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
    interact: Interact,
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

pub type AccessTokenResponse {
  AccessTokenResponse(
    value: String,
    manage: String,
    expires_in: Option(Int),
    access: List(Access),
  )
}

/// The result of a grant request. A grant is either pending client
/// interaction (`PendingGrant`) or has already been approved (`Grant`).
/// See https://openpayments.dev/apis/auth-server/operations/post-request/
pub type GrantResponse {
  PendingGrant(interact: InteractResponse, continue: ContinueResponse)
  Grant(access_token: AccessTokenResponse, continue: ContinueResponse)
}

fn optional_field(
  fields: List(#(String, Json)),
  name: String,
  value: Option(a),
  encode: fn(a) -> Json,
) -> List(#(String, Json)) {
  case value {
    Some(v) -> [#(name, encode(v)), ..fields]
    None -> fields
  }
}

fn encode_amount(amount: Amount) -> Json {
  json.object([
    #("value", json.int(amount.value)),
    #("assetCode", json.string(amount.asset_code)),
    #("assetScale", json.int(amount.asset_scale)),
  ])
}

fn encode_limits(limits: Limits) -> Json {
  let fields =
    []
    |> optional_field("receiver", limits.receiver, json.string)
    |> optional_field("interval", limits.interval, json.string)

  let fields = case limits.amount {
    NoAmount -> fields
    DebitAmount(amount) -> [#("debitAmount", encode_amount(amount)), ..fields]
    ReceiveAmount(amount) -> [
      #("receiveAmount", encode_amount(amount)),
      ..fields
    ]
  }
  json.object(fields)
}

fn encode_incoming_action(action: IncomingAction) -> Json {
  json.string(case action {
    IncomingCreate -> "create"
    IncomingComplete -> "complete"
    IncomingRead -> "read"
    IncomingReadAll -> "read-all"
    IncomingList -> "list"
    IncomingListAll -> "list-all"
  })
}

fn encode_outgoing_action(action: OutgoingAction) -> Json {
  json.string(case action {
    OutgoingCreate -> "create"
    OutgoingRead -> "read"
    OutgoingReadAll -> "read-all"
    OutgoingList -> "list"
    OutgoingListAll -> "list-all"
  })
}

fn encode_quote_action(action: QuoteAction) -> Json {
  json.string(case action {
    QuoteCreate -> "create"
    QuoteRead -> "read"
    QuoteReadAll -> "read-all"
  })
}

fn encode_access(access: Access) -> Json {
  case access {
    AccessIncoming(actions, identifier) ->
      [
        #("type", json.string("incoming-payment")),
        #("actions", json.array(actions, encode_incoming_action)),
      ]
      |> optional_field("identifier", identifier, json.string)
      |> json.object
    AccessOutgoing(actions, identifier, limits) ->
      [
        #("type", json.string("outgoing-payment")),
        #("actions", json.array(actions, encode_outgoing_action)),
        #("identifier", json.string(identifier)),
      ]
      |> optional_field("limits", limits, encode_limits)
      |> json.object
    AccessQuote(actions) ->
      json.object([
        #("type", json.string("quote")),
        #("actions", json.array(actions, encode_quote_action)),
      ])
  }
}

fn encode_finish(finish: Finish) -> Json {
  json.object([
    #("method", json.string(finish.method)),
    #("uri", json.string(finish.uri)),
    #("nonce", json.string(finish.nonce)),
  ])
}

fn encode_interact(interact: Interact) -> Json {
  [#("start", json.array(interact.start, json.string))]
  |> optional_field("finish", interact.finish, encode_finish)
  |> json.object
}

fn encode_access_token(access_token: AccessTokenBodyProperty) -> Json {
  json.object([#("access", json.array([access_token.access], encode_access))])
}

fn encode_key(key: Key) -> Json {
  json.object([
    #("kid", json.string(key.kid)),
    #("x", json.string(key.x)),
    #("alg", json.string(key.alg)),
    #("kty", json.string(key.kty)),
    #("crv", json.string(key.crv)),
  ])
}

fn encode_client(client: ClientType) -> Json {
  case client {
    ClientDirectedIdentity(jwk) -> encode_key(jwk)
    ClientWalletAddressObject(wallet_address) -> json.string(wallet_address)
  }
}

fn encode_body(body: Body) -> Json {
  json.object([
    #("access_token", encode_access_token(body.access_token)),
    #("client", encode_client(body.client)),
    #("interact", encode_interact(body.interact)),
  ])
}

fn decode_incoming_action() -> decode.Decoder(IncomingAction) {
  use action <- decode.then(decode.string)
  case action {
    "create" -> decode.success(IncomingCreate)
    "complete" -> decode.success(IncomingComplete)
    "read" -> decode.success(IncomingRead)
    "read-all" -> decode.success(IncomingReadAll)
    "list" -> decode.success(IncomingList)
    "list-all" -> decode.success(IncomingListAll)
    _ -> decode.failure(IncomingCreate, "IncomingAction")
  }
}

fn decode_outgoing_action() -> decode.Decoder(OutgoingAction) {
  use action <- decode.then(decode.string)
  case action {
    "create" -> decode.success(OutgoingCreate)
    "read" -> decode.success(OutgoingRead)
    "read-all" -> decode.success(OutgoingReadAll)
    "list" -> decode.success(OutgoingList)
    "list-all" -> decode.success(OutgoingListAll)
    _ -> decode.failure(OutgoingCreate, "OutgoingAction")
  }
}

fn decode_quote_action() -> decode.Decoder(QuoteAction) {
  use action <- decode.then(decode.string)
  case action {
    "create" -> decode.success(QuoteCreate)
    "read" -> decode.success(QuoteRead)
    "read-all" -> decode.success(QuoteReadAll)
    _ -> decode.failure(QuoteCreate, "QuoteAction")
  }
}

fn decode_amount() -> decode.Decoder(Amount) {
  use value <- decode.field("value", decode.int)
  use asset_code <- decode.field("assetCode", decode.string)
  use asset_scale <- decode.field("assetScale", decode.int)
  decode.success(Amount(
    value: value,
    asset_code: asset_code,
    asset_scale: asset_scale,
  ))
}

fn decode_limits() -> decode.Decoder(Limits) {
  use receiver <- decode.optional_field(
    "receiver",
    None,
    decode.string |> decode.map(Some),
  )
  use interval <- decode.optional_field(
    "interval",
    None,
    decode.string |> decode.map(Some),
  )
  use debit_amount <- decode.optional_field(
    "debitAmount",
    None,
    decode_amount() |> decode.map(Some),
  )
  use receive_amount <- decode.optional_field(
    "receiveAmount",
    None,
    decode_amount() |> decode.map(Some),
  )
  let amount = case debit_amount, receive_amount {
    Some(amount), _ -> DebitAmount(amount)
    _, Some(amount) -> ReceiveAmount(amount)
    None, None -> NoAmount
  }
  decode.success(Limits(receiver: receiver, interval: interval, amount: amount))
}

fn decode_access() -> decode.Decoder(Access) {
  use kind <- decode.field("type", decode.string)
  case kind {
    "incoming-payment" -> {
      use actions <- decode.field(
        "actions",
        decode.list(decode_incoming_action()),
      )
      use identifier <- decode.optional_field(
        "identifier",
        None,
        decode.string |> decode.map(Some),
      )
      decode.success(AccessIncoming(actions, identifier))
    }
    "outgoing-payment" -> {
      use actions <- decode.field(
        "actions",
        decode.list(decode_outgoing_action()),
      )
      use identifier <- decode.field("identifier", decode.string)
      use limits <- decode.optional_field(
        "limits",
        None,
        decode_limits() |> decode.map(Some),
      )
      decode.success(AccessOutgoing(actions, identifier, limits))
    }
    "quote" -> {
      use actions <- decode.field("actions", decode.list(decode_quote_action()))
      decode.success(AccessQuote(actions))
    }
    _ -> decode.failure(AccessQuote([]), "Access")
  }
}

fn decode_interact_response() -> decode.Decoder(InteractResponse) {
  use redirect <- decode.field("redirect", decode.string)
  use finish <- decode.optional_field(
    "finish",
    None,
    decode.string |> decode.map(Some),
  )
  decode.success(InteractResponse(redirect: redirect, finish: finish))
}

fn decode_continue_access_token() -> decode.Decoder(ContinueAccessToken) {
  use value <- decode.field("value", decode.string)
  decode.success(ContinueAccessToken(value: value))
}

fn decode_continue_response() -> decode.Decoder(ContinueResponse) {
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

fn decode_access_token_response() -> decode.Decoder(AccessTokenResponse) {
  use value <- decode.field("value", decode.string)
  use manage <- decode.field("manage", decode.string)
  use expires_in <- decode.optional_field(
    "expires_in",
    None,
    decode.int |> decode.map(Some),
  )
  use access <- decode.field("access", decode.list(decode_access()))
  decode.success(AccessTokenResponse(
    value: value,
    manage: manage,
    expires_in: expires_in,
    access: access,
  ))
}

fn decode_pending_grant() -> decode.Decoder(GrantResponse) {
  use interact <- decode.field("interact", decode_interact_response())
  use continue <- decode.field("continue", decode_continue_response())
  decode.success(PendingGrant(interact: interact, continue: continue))
}

fn decode_grant() -> decode.Decoder(GrantResponse) {
  use access_token <- decode.field(
    "access_token",
    decode_access_token_response(),
  )
  use continue <- decode.field("continue", decode_continue_response())
  decode.success(Grant(access_token: access_token, continue: continue))
}

fn decode_grant_response() -> decode.Decoder(GrantResponse) {
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
    body,
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
