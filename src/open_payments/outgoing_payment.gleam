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

/// See https://openpayments.dev/apis/resource-server/operations/get-outgoing-payment/
pub type OutgoingPayment {
  OutgoingPayment(
    id: String,
    wallet_address: String,
    quote_id: Option(String),
    failed: Bool,
    receiver: String,
    receive_amount: Amount,
    debit_amount: Amount,
    sent_amount: Amount,
    grant_spent_debit_amount: Option(Amount),
    grant_spent_receive_amount: Option(Amount),
    metadata: Option(Dynamic),
    created_at: String,
  )
}

pub type OutgoingPaymentList {
  OutgoingPaymentList(pagination: PageInfo, result: List(OutgoingPayment))
}

/// The subset of the outgoing payment fields accepted when creating one.
/// An outgoing payment is created either from a quote, or directly from an
/// incoming payment with an explicit `debitAmount`.
pub type CreateSource {
  FromQuote(quote_id: String)
  FromIncomingPayment(incoming_payment: String, debit_amount: Amount)
}

pub type CreateOptions {
  CreateOptions(
    resource_server: String,
    wallet_address: String,
    source: CreateSource,
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

/// The spent amounts for the current outgoing payment grant, as identified
/// by the presented access token.
pub type GrantSpentAmounts {
  GrantSpentAmounts(
    spent_receive_amount: Option(Amount),
    spent_debit_amount: Option(Amount),
  )
}

fn encode_create_body(options: CreateOptions) -> Json {
  let fields = [#("walletAddress", json.string(options.wallet_address))]

  let fields = case options.source {
    FromQuote(quote_id) -> [#("quoteId", json.string(quote_id)), ..fields]
    FromIncomingPayment(incoming_payment, debit_amount) -> [
      #("debitAmount", encode_amount(debit_amount)),
      #("incomingPayment", json.string(incoming_payment)),
      ..fields
    ]
  }

  fields
  |> optional_field("metadata", options.metadata, fn(m) { m })
  |> json.object
}

fn decode_outgoing_payment() -> decode.Decoder(OutgoingPayment) {
  use id <- decode.field("id", decode.string)
  use wallet_address <- decode.field("walletAddress", decode.string)
  use quote_id <- decode.optional_field(
    "quoteId",
    None,
    decode.string |> decode.map(Some),
  )
  use failed <- decode.optional_field("failed", False, decode.bool)
  use receiver <- decode.field("receiver", decode.string)
  use receive_amount <- decode.field("receiveAmount", decode_amount())
  use debit_amount <- decode.field("debitAmount", decode_amount())
  use sent_amount <- decode.field("sentAmount", decode_amount())
  use grant_spent_debit_amount <- decode.optional_field(
    "grantSpentDebitAmount",
    None,
    decode_amount() |> decode.map(Some),
  )
  use grant_spent_receive_amount <- decode.optional_field(
    "grantSpentReceiveAmount",
    None,
    decode_amount() |> decode.map(Some),
  )
  use metadata <- decode.optional_field(
    "metadata",
    None,
    decode.dynamic |> decode.map(Some),
  )
  use created_at <- decode.field("createdAt", decode.string)
  decode.success(OutgoingPayment(
    id: id,
    wallet_address: wallet_address,
    quote_id: quote_id,
    failed: failed,
    receiver: receiver,
    receive_amount: receive_amount,
    debit_amount: debit_amount,
    sent_amount: sent_amount,
    grant_spent_debit_amount: grant_spent_debit_amount,
    grant_spent_receive_amount: grant_spent_receive_amount,
    metadata: metadata,
    created_at: created_at,
  ))
}

fn decode_outgoing_payment_list() -> decode.Decoder(OutgoingPaymentList) {
  use pagination <- decode.field("pagination", decode_page_info())
  use result <- decode.field("result", decode.list(decode_outgoing_payment()))
  decode.success(OutgoingPaymentList(pagination: pagination, result: result))
}

fn decode_grant_spent_amounts() -> decode.Decoder(GrantSpentAmounts) {
  use spent_receive_amount <- decode.field(
    "spentReceiveAmount",
    decode.optional(decode_amount()),
  )
  use spent_debit_amount <- decode.field(
    "spentDebitAmount",
    decode.optional(decode_amount()),
  )
  decode.success(GrantSpentAmounts(
    spent_receive_amount: spent_receive_amount,
    spent_debit_amount: spent_debit_amount,
  ))
}

/// Creates a new outgoing payment on the given wallet address, either from
/// a quote or directly from an incoming payment.
/// See https://openpayments.dev/apis/resource-server/operations/create-outgoing-payment/
pub fn create(
  client: Client,
  access_token: String,
  options: CreateOptions,
) -> Result(OutgoingPayment, String) {
  let url = options.resource_server <> "/outgoing-payments"
  let body = encode_create_body(options)

  use response_body <- result.try(request.send_request(
    client,
    url,
    http.Post,
    Some(body),
    token: Some(access_token),
  ))

  json.parse(response_body, decode_outgoing_payment())
  |> result.map_error(fn(_) { "Failed to parse outgoing payment response" })
}

/// Lists the outgoing payments on the given wallet address.
/// See https://openpayments.dev/apis/resource-server/operations/list-outgoing-payments/
pub fn list(
  client: Client,
  access_token: String,
  options: ListOptions,
) -> Result(OutgoingPaymentList, String) {
  let query =
    [#("wallet-address", options.wallet_address)]
    |> add_query("cursor", options.cursor, fn(v) { v })
    |> add_query("first", options.first, int.to_string)
    |> add_query("last", options.last, int.to_string)

  let url =
    options.resource_server
    <> "/outgoing-payments?"
    <> uri.query_to_string(query)

  use response_body <- result.try(request.send_request(
    client,
    url,
    http.Get,
    None,
    token: Some(access_token),
  ))

  json.parse(response_body, decode_outgoing_payment_list())
  |> result.map_error(fn(_) { "Failed to parse outgoing payment list response" })
}

/// Fetches the latest state of an outgoing payment.
/// `id` is the full outgoing payment URL, as returned by `create`.
/// See https://openpayments.dev/apis/resource-server/operations/get-outgoing-payment/
pub fn get(
  client: Client,
  access_token: String,
  id: String,
) -> Result(OutgoingPayment, String) {
  use response_body <- result.try(request.send_request(
    client,
    id,
    http.Get,
    None,
    token: Some(access_token),
  ))

  json.parse(response_body, decode_outgoing_payment())
  |> result.map_error(fn(_) { "Failed to parse outgoing payment response" })
}

/// Fetches the amounts already spent under the outgoing payment grant
/// identified by the given access token.
/// See https://openpayments.dev/apis/resource-server/operations/get-outgoing-payment-grant/
pub fn get_grant_spent_amounts(
  client: Client,
  access_token: String,
  resource_server: String,
) -> Result(GrantSpentAmounts, String) {
  let url = resource_server <> "/outgoing-payment-grant"

  use response_body <- result.try(request.send_request(
    client,
    url,
    http.Get,
    None,
    token: Some(access_token),
  ))

  json.parse(response_body, decode_grant_spent_amounts())
  |> result.map_error(fn(_) {
    "Failed to parse outgoing payment grant response"
  })
}
