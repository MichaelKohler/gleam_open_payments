import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}

pub type Key {
  Key(kid: String, x: String, alg: String, kty: String, crv: String)
}

pub type Amount {
  Amount(value: String, asset_code: String, asset_scale: Int)
}

/// A `debitAmount`/`receiveAmount` pair, of which at most one is present.
/// Shared by outgoing payment grant limits and quote creation.
pub type AmountOption {
  NoAmount
  DebitAmount(Amount)
  ReceiveAmount(Amount)
}

/// Prepends `#(name, encode(v))` to `fields` when `value` is `Some(v)`,
/// otherwise leaves `fields` unchanged. Used to build JSON objects with
/// optional fields.
pub fn optional_field(
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

pub fn encode_amount(amount: Amount) -> Json {
  json.object([
    #("value", json.string(amount.value)),
    #("assetCode", json.string(amount.asset_code)),
    #("assetScale", json.int(amount.asset_scale)),
  ])
}

pub fn decode_amount() -> decode.Decoder(Amount) {
  use value <- decode.field("value", decode.string)
  use asset_code <- decode.field("assetCode", decode.string)
  use asset_scale <- decode.field("assetScale", decode.int)
  decode.success(Amount(
    value: value,
    asset_code: asset_code,
    asset_scale: asset_scale,
  ))
}

/// Prepends the encoded `debitAmount` or `receiveAmount` field to `fields`
/// when `amount` carries one, otherwise leaves `fields` unchanged.
pub fn add_amount_option(
  fields: List(#(String, Json)),
  amount: AmountOption,
) -> List(#(String, Json)) {
  case amount {
    NoAmount -> fields
    DebitAmount(amount) -> [#("debitAmount", encode_amount(amount)), ..fields]
    ReceiveAmount(amount) -> [
      #("receiveAmount", encode_amount(amount)),
      ..fields
    ]
  }
}

pub fn decode_amount_option() -> decode.Decoder(AmountOption) {
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
  case debit_amount, receive_amount {
    Some(amount), _ -> decode.success(DebitAmount(amount))
    _, Some(amount) -> decode.success(ReceiveAmount(amount))
    None, None -> decode.success(NoAmount)
  }
}

/// Cursor pagination info shared by list responses.
pub type PageInfo {
  PageInfo(
    start_cursor: Option(String),
    end_cursor: Option(String),
    has_next_page: Bool,
    has_previous_page: Bool,
  )
}

pub fn decode_page_info() -> decode.Decoder(PageInfo) {
  use start_cursor <- decode.optional_field(
    "startCursor",
    None,
    decode.string |> decode.map(Some),
  )
  use end_cursor <- decode.optional_field(
    "endCursor",
    None,
    decode.string |> decode.map(Some),
  )
  use has_next_page <- decode.field("hasNextPage", decode.bool)
  use has_previous_page <- decode.field("hasPreviousPage", decode.bool)
  decode.success(PageInfo(
    start_cursor: start_cursor,
    end_cursor: end_cursor,
    has_next_page: has_next_page,
    has_previous_page: has_previous_page,
  ))
}

/// Prepends `#(name, value)` to `query` when `value` is `Some(v)`, otherwise
/// leaves `query` unchanged. Used to build query strings with optional
/// parameters.
pub fn add_query(
  query: List(#(String, String)),
  name: String,
  value: Option(a),
  encode: fn(a) -> String,
) -> List(#(String, String)) {
  case value {
    Some(v) -> [#(name, encode(v)), ..query]
    None -> query
  }
}

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

pub type Limits {
  Limits(
    receiver: Option(String),
    interval: Option(String),
    amount: AmountOption,
  )
}

/// The access rights granted to (or requested for) an access token.
/// Shared by grant requests and access token responses.
pub type Access {
  AccessIncoming(actions: List(IncomingAction), identifier: Option(String))
  AccessOutgoing(
    actions: List(OutgoingAction),
    identifier: String,
    limits: Option(Limits),
  )
  AccessQuote(actions: List(QuoteAction))
}

/// See https://openpayments.dev/apis/auth-server/operations/post-token/
pub type AccessTokenResponse {
  AccessTokenResponse(
    value: String,
    manage: String,
    expires_in: Option(Int),
    access: List(Access),
  )
}

pub fn encode_limits(limits: Limits) -> Json {
  []
  |> optional_field("receiver", limits.receiver, json.string)
  |> optional_field("interval", limits.interval, json.string)
  |> add_amount_option(limits.amount)
  |> json.object
}

pub fn encode_incoming_action(action: IncomingAction) -> Json {
  json.string(case action {
    IncomingCreate -> "create"
    IncomingComplete -> "complete"
    IncomingRead -> "read"
    IncomingReadAll -> "read-all"
    IncomingList -> "list"
    IncomingListAll -> "list-all"
  })
}

pub fn encode_outgoing_action(action: OutgoingAction) -> Json {
  json.string(case action {
    OutgoingCreate -> "create"
    OutgoingRead -> "read"
    OutgoingReadAll -> "read-all"
    OutgoingList -> "list"
    OutgoingListAll -> "list-all"
  })
}

pub fn encode_quote_action(action: QuoteAction) -> Json {
  json.string(case action {
    QuoteCreate -> "create"
    QuoteRead -> "read"
    QuoteReadAll -> "read-all"
  })
}

pub fn encode_access(access: Access) -> Json {
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

pub fn decode_incoming_action() -> decode.Decoder(IncomingAction) {
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

pub fn decode_outgoing_action() -> decode.Decoder(OutgoingAction) {
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

pub fn decode_quote_action() -> decode.Decoder(QuoteAction) {
  use action <- decode.then(decode.string)
  case action {
    "create" -> decode.success(QuoteCreate)
    "read" -> decode.success(QuoteRead)
    "read-all" -> decode.success(QuoteReadAll)
    _ -> decode.failure(QuoteCreate, "QuoteAction")
  }
}

pub fn decode_limits() -> decode.Decoder(Limits) {
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
  use amount <- decode.then(decode_amount_option())
  decode.success(Limits(receiver: receiver, interval: interval, amount: amount))
}

pub fn decode_access() -> decode.Decoder(Access) {
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

pub fn decode_access_token_response() -> decode.Decoder(AccessTokenResponse) {
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
