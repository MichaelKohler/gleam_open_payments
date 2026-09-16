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
