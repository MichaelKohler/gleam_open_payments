import gleam/dynamic/decode
import gleam/http
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import gleam/result
import open_payments/client.{type Client}
import open_payments/request
import open_payments/types.{
  type Amount, type AmountOption, add_amount_option, decode_amount,
}

/// See https://openpayments.dev/apis/resource-server/operations/get-quote/
pub type Quote {
  Quote(
    id: String,
    wallet_address: String,
    receiver: String,
    debit_amount: Amount,
    receive_amount: Amount,
    method: String,
    created_at: String,
    expires_at: Option(String),
  )
}

pub type CreateOptions {
  CreateOptions(
    resource_server: String,
    wallet_address: String,
    receiver: String,
    amount: AmountOption,
  )
}

@internal
pub fn encode_create_body(options: CreateOptions) -> Json {
  [
    #("walletAddress", json.string(options.wallet_address)),
    #("receiver", json.string(options.receiver)),
    #("method", json.string("ilp")),
  ]
  |> add_amount_option(options.amount)
  |> json.object
}

@internal
pub fn decode_quote() -> decode.Decoder(Quote) {
  use id <- decode.field("id", decode.string)
  use wallet_address <- decode.field("walletAddress", decode.string)
  use receiver <- decode.field("receiver", decode.string)
  use debit_amount <- decode.field("debitAmount", decode_amount())
  use receive_amount <- decode.field("receiveAmount", decode_amount())
  use method <- decode.field("method", decode.string)
  use created_at <- decode.field("createdAt", decode.string)
  use expires_at <- decode.optional_field(
    "expiresAt",
    None,
    decode.string |> decode.map(Some),
  )
  decode.success(Quote(
    id: id,
    wallet_address: wallet_address,
    receiver: receiver,
    debit_amount: debit_amount,
    receive_amount: receive_amount,
    method: method,
    created_at: created_at,
    expires_at: expires_at,
  ))
}

/// Creates a new quote for a payment to the given incoming payment.
/// See https://openpayments.dev/apis/resource-server/operations/create-quote/
pub fn create(
  client: Client,
  access_token: String,
  options: CreateOptions,
) -> Result(Quote, String) {
  let url = options.resource_server <> "/quotes"
  let body = encode_create_body(options)

  use response_body <- result.try(request.send_request(
    client,
    url,
    http.Post,
    Some(body),
    token: Some(access_token),
  ))

  json.parse(response_body, decode_quote())
  |> result.map_error(fn(_) { "Failed to parse quote response" })
}

/// Fetches the latest state of a quote.
/// `id` is the full quote URL, as returned by `create`.
/// See https://openpayments.dev/apis/resource-server/operations/get-quote/
pub fn get(
  client: Client,
  access_token: String,
  id: String,
) -> Result(Quote, String) {
  use response_body <- result.try(request.send_request(
    client,
    id,
    http.Get,
    None,
    token: Some(access_token),
  ))

  json.parse(response_body, decode_quote())
  |> result.map_error(fn(_) { "Failed to parse quote response" })
}
