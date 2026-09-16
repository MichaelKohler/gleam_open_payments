import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/http
import gleam/int
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/uri
import open_payments/client.{type Client}
import open_payments/request
import open_payments/types.{
  type Amount, type PageInfo, add_query, decode_amount, decode_page_info,
  encode_amount, optional_field,
}

pub type IlpPaymentMethod {
  IlpPaymentMethod(ilp_address: String, shared_secret: String)
}

/// See https://openpayments.dev/apis/resource-server/operations/get-incoming-payment/
pub type IncomingPayment {
  IncomingPayment(
    id: String,
    wallet_address: String,
    completed: Bool,
    incoming_amount: Option(Amount),
    received_amount: Amount,
    expires_at: Option(String),
    metadata: Option(Dynamic),
    created_at: String,
    methods: List(IlpPaymentMethod),
  )
}

pub type IncomingPaymentList {
  IncomingPaymentList(pagination: PageInfo, result: List(IncomingPayment))
}

pub type CreateOptions {
  CreateOptions(
    resource_server: String,
    wallet_address: String,
    incoming_amount: Option(Amount),
    expires_at: Option(String),
    metadata: Option(Json),
  )
}

pub type ListOptions {
  ListOptions(
    resource_server: String,
    wallet_address: String,
    cursor: Option(String),
    first: Option(Int),
    last: Option(Int),
  )
}

@internal
pub fn encode_create_body(options: CreateOptions) -> Json {
  [#("walletAddress", json.string(options.wallet_address))]
  |> optional_field("incomingAmount", options.incoming_amount, encode_amount)
  |> optional_field("expiresAt", options.expires_at, json.string)
  |> optional_field("metadata", options.metadata, fn(m) { m })
  |> json.object
}

@internal
pub fn decode_ilp_payment_method() -> decode.Decoder(IlpPaymentMethod) {
  use ilp_address <- decode.field("ilpAddress", decode.string)
  use shared_secret <- decode.field("sharedSecret", decode.string)
  decode.success(IlpPaymentMethod(
    ilp_address: ilp_address,
    shared_secret: shared_secret,
  ))
}

@internal
pub fn decode_incoming_payment() -> decode.Decoder(IncomingPayment) {
  use id <- decode.field("id", decode.string)
  use wallet_address <- decode.field("walletAddress", decode.string)
  use completed <- decode.field("completed", decode.bool)
  use incoming_amount <- decode.optional_field(
    "incomingAmount",
    None,
    decode_amount() |> decode.map(Some),
  )
  use received_amount <- decode.field("receivedAmount", decode_amount())
  use expires_at <- decode.optional_field(
    "expiresAt",
    None,
    decode.string |> decode.map(Some),
  )
  use metadata <- decode.optional_field(
    "metadata",
    None,
    decode.dynamic |> decode.map(Some),
  )
  use created_at <- decode.field("createdAt", decode.string)
  use methods <- decode.optional_field(
    "methods",
    [],
    decode.list(decode_ilp_payment_method()),
  )
  decode.success(IncomingPayment(
    id: id,
    wallet_address: wallet_address,
    completed: completed,
    incoming_amount: incoming_amount,
    received_amount: received_amount,
    expires_at: expires_at,
    metadata: metadata,
    created_at: created_at,
    methods: methods,
  ))
}

@internal
pub fn decode_incoming_payment_list() -> decode.Decoder(IncomingPaymentList) {
  use pagination <- decode.field("pagination", decode_page_info())
  use result <- decode.field("result", decode.list(decode_incoming_payment()))
  decode.success(IncomingPaymentList(pagination: pagination, result: result))
}

/// Creates a new incoming payment on the given wallet address.
/// See https://openpayments.dev/apis/resource-server/operations/create-incoming-payment/
pub fn create(
  client: Client,
  access_token: String,
  options: CreateOptions,
) -> Result(IncomingPayment, String) {
  let url = options.resource_server <> "/incoming-payments"
  let body = encode_create_body(options)

  use response_body <- result.try(request.send_request(
    client,
    url,
    http.Post,
    Some(body),
    token: Some(access_token),
  ))

  json.parse(response_body, decode_incoming_payment())
  |> result.map_error(fn(_) { "Failed to parse incoming payment response" })
}

/// Lists the incoming payments on the given wallet address.
/// See https://openpayments.dev/apis/resource-server/operations/list-incoming-payments/
pub fn list(
  client: Client,
  access_token: String,
  options: ListOptions,
) -> Result(IncomingPaymentList, String) {
  let query =
    [#("wallet-address", options.wallet_address)]
    |> add_query("cursor", options.cursor, fn(v) { v })
    |> add_query("first", options.first, int.to_string)
    |> add_query("last", options.last, int.to_string)

  let url =
    options.resource_server
    <> "/incoming-payments?"
    <> uri.query_to_string(query)

  use response_body <- result.try(request.send_request(
    client,
    url,
    http.Get,
    None,
    token: Some(access_token),
  ))

  json.parse(response_body, decode_incoming_payment_list())
  |> result.map_error(fn(_) { "Failed to parse incoming payment list response" })
}

/// Fetches the latest state of an incoming payment.
/// `id` is the full incoming payment URL, as returned by `create`.
/// See https://openpayments.dev/apis/resource-server/operations/get-incoming-payment/
pub fn get(
  client: Client,
  access_token: String,
  id: String,
) -> Result(IncomingPayment, String) {
  use response_body <- result.try(request.send_request(
    client,
    id,
    http.Get,
    None,
    token: Some(access_token),
  ))

  json.parse(response_body, decode_incoming_payment())
  |> result.map_error(fn(_) { "Failed to parse incoming payment response" })
}

/// Marks an incoming payment as completed, so that it will no longer accept
/// any further payments.
/// `id` is the full incoming payment URL, as returned by `create`.
/// See https://openpayments.dev/apis/resource-server/operations/complete-incoming-payment/
pub fn complete(
  client: Client,
  access_token: String,
  id: String,
) -> Result(IncomingPayment, String) {
  let url = id <> "/complete"

  use response_body <- result.try(request.send_request(
    client,
    url,
    http.Post,
    None,
    token: Some(access_token),
  ))

  json.parse(response_body, decode_incoming_payment())
  |> result.map_error(fn(_) { "Failed to parse incoming payment response" })
}
