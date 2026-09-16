import gleam/json
import gleam/option.{None, Some}
import open_payments/quotes.{CreateOptions, Quote}
import open_payments/types.{Amount, DebitAmount, NoAmount}

pub fn encode_create_body_test() {
  let options =
    CreateOptions(
      resource_server: "https://resource.example",
      wallet_address: "https://wallet.example/sender",
      receiver: "https://resource.example/incoming-payments/1",
      amount: DebitAmount(Amount("500", "USD", 2)),
    )

  assert json.to_string(quotes.encode_create_body(options))
    == "{\"debitAmount\":{\"value\":\"500\",\"assetCode\":\"USD\",\"assetScale\":2},\"walletAddress\":\"https://wallet.example/sender\",\"receiver\":\"https://resource.example/incoming-payments/1\",\"method\":\"ilp\"}"
}

pub fn encode_create_body_no_amount_test() {
  let options =
    CreateOptions(
      resource_server: "https://resource.example",
      wallet_address: "https://wallet.example/sender",
      receiver: "https://resource.example/incoming-payments/1",
      amount: NoAmount,
    )

  assert json.to_string(quotes.encode_create_body(options))
    == "{\"walletAddress\":\"https://wallet.example/sender\",\"receiver\":\"https://resource.example/incoming-payments/1\",\"method\":\"ilp\"}"
}

pub fn decode_quote_test() {
  let json_value =
    json.object([
      #("id", json.string("https://resource.example/quotes/1")),
      #("walletAddress", json.string("https://wallet.example/sender")),
      #("receiver", json.string("https://resource.example/incoming-payments/1")),
      #("debitAmount", types.encode_amount(Amount("500", "USD", 2))),
      #("receiveAmount", types.encode_amount(Amount("480", "EUR", 2))),
      #("method", json.string("ilp")),
      #("createdAt", json.string("2024-01-01T00:00:00Z")),
      #("expiresAt", json.string("2024-01-01T00:05:00Z")),
    ])

  assert json.parse(json.to_string(json_value), quotes.decode_quote())
    == Ok(Quote(
      id: "https://resource.example/quotes/1",
      wallet_address: "https://wallet.example/sender",
      receiver: "https://resource.example/incoming-payments/1",
      debit_amount: Amount("500", "USD", 2),
      receive_amount: Amount("480", "EUR", 2),
      method: "ilp",
      created_at: "2024-01-01T00:00:00Z",
      expires_at: Some("2024-01-01T00:05:00Z"),
    ))
}

pub fn decode_quote_without_expiry_test() {
  let json_value =
    json.object([
      #("id", json.string("https://resource.example/quotes/1")),
      #("walletAddress", json.string("https://wallet.example/sender")),
      #("receiver", json.string("https://resource.example/incoming-payments/1")),
      #("debitAmount", types.encode_amount(Amount("500", "USD", 2))),
      #("receiveAmount", types.encode_amount(Amount("480", "EUR", 2))),
      #("method", json.string("ilp")),
      #("createdAt", json.string("2024-01-01T00:00:00Z")),
    ])

  assert json.parse(json.to_string(json_value), quotes.decode_quote())
    == Ok(Quote(
      id: "https://resource.example/quotes/1",
      wallet_address: "https://wallet.example/sender",
      receiver: "https://resource.example/incoming-payments/1",
      debit_amount: Amount("500", "USD", 2),
      receive_amount: Amount("480", "EUR", 2),
      method: "ilp",
      created_at: "2024-01-01T00:00:00Z",
      expires_at: None,
    ))
}
