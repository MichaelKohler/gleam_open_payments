import gleam/json
import gleam/option.{None, Some}
import open_payments/outgoing_payment.{
  CreateOptions, FromIncomingPayment, FromQuote, GrantSpentAmounts,
  OutgoingPayment,
}
import open_payments/types.{Amount}

pub fn encode_create_body_from_quote_test() {
  let options =
    CreateOptions(
      resource_server: "https://resource.example",
      wallet_address: "https://wallet.example/sender",
      source: FromQuote("https://resource.example/quotes/1"),
      metadata: None,
    )

  assert json.to_string(outgoing_payment.encode_create_body(options))
    == "{\"quoteId\":\"https://resource.example/quotes/1\",\"walletAddress\":\"https://wallet.example/sender\"}"
}

pub fn encode_create_body_from_incoming_payment_test() {
  let options =
    CreateOptions(
      resource_server: "https://resource.example",
      wallet_address: "https://wallet.example/sender",
      source: FromIncomingPayment(
        "https://resource.example/incoming-payments/1",
        Amount("500", "USD", 2),
      ),
      metadata: None,
    )

  assert json.to_string(outgoing_payment.encode_create_body(options))
    == "{\"debitAmount\":{\"value\":\"500\",\"assetCode\":\"USD\",\"assetScale\":2},\"incomingPayment\":\"https://resource.example/incoming-payments/1\",\"walletAddress\":\"https://wallet.example/sender\"}"
}

pub fn decode_outgoing_payment_test() {
  let json_value =
    json.object([
      #("id", json.string("https://resource.example/outgoing-payments/1")),
      #("walletAddress", json.string("https://wallet.example/sender")),
      #("quoteId", json.string("https://resource.example/quotes/1")),
      #("failed", json.bool(False)),
      #("receiver", json.string("https://resource.example/incoming-payments/1")),
      #("receiveAmount", types.encode_amount(Amount("480", "EUR", 2))),
      #("debitAmount", types.encode_amount(Amount("500", "USD", 2))),
      #("sentAmount", types.encode_amount(Amount("0", "USD", 2))),
      #("createdAt", json.string("2024-01-01T00:00:00Z")),
    ])

  assert json.parse(
      json.to_string(json_value),
      outgoing_payment.decode_outgoing_payment(),
    )
    == Ok(OutgoingPayment(
      id: "https://resource.example/outgoing-payments/1",
      wallet_address: "https://wallet.example/sender",
      quote_id: Some("https://resource.example/quotes/1"),
      failed: False,
      receiver: "https://resource.example/incoming-payments/1",
      receive_amount: Amount("480", "EUR", 2),
      debit_amount: Amount("500", "USD", 2),
      sent_amount: Amount("0", "USD", 2),
      grant_spent_debit_amount: None,
      grant_spent_receive_amount: None,
      metadata: None,
      created_at: "2024-01-01T00:00:00Z",
    ))
}

pub fn decode_outgoing_payment_defaults_test() {
  let json_value =
    json.object([
      #("id", json.string("https://resource.example/outgoing-payments/1")),
      #("walletAddress", json.string("https://wallet.example/sender")),
      #("receiver", json.string("https://resource.example/incoming-payments/1")),
      #("receiveAmount", types.encode_amount(Amount("480", "EUR", 2))),
      #("debitAmount", types.encode_amount(Amount("500", "USD", 2))),
      #("sentAmount", types.encode_amount(Amount("0", "USD", 2))),
      #("createdAt", json.string("2024-01-01T00:00:00Z")),
    ])

  assert json.parse(
      json.to_string(json_value),
      outgoing_payment.decode_outgoing_payment(),
    )
    == Ok(OutgoingPayment(
      id: "https://resource.example/outgoing-payments/1",
      wallet_address: "https://wallet.example/sender",
      quote_id: None,
      failed: False,
      receiver: "https://resource.example/incoming-payments/1",
      receive_amount: Amount("480", "EUR", 2),
      debit_amount: Amount("500", "USD", 2),
      sent_amount: Amount("0", "USD", 2),
      grant_spent_debit_amount: None,
      grant_spent_receive_amount: None,
      metadata: None,
      created_at: "2024-01-01T00:00:00Z",
    ))
}

pub fn decode_outgoing_payment_list_test() {
  let json_value =
    json.object([
      #(
        "pagination",
        json.object([
          #("hasNextPage", json.bool(True)),
          #("hasPreviousPage", json.bool(False)),
        ]),
      ),
      #("result", json.array([], fn(_) { json.null() })),
    ])

  let assert Ok(decoded) =
    json.parse(
      json.to_string(json_value),
      outgoing_payment.decode_outgoing_payment_list(),
    )

  assert decoded.result == []
  assert decoded.pagination.has_next_page == True
}

pub fn decode_grant_spent_amounts_test() {
  let json_value =
    json.object([
      #("spentReceiveAmount", types.encode_amount(Amount("100", "EUR", 2))),
      #("spentDebitAmount", json.null()),
    ])

  assert json.parse(
      json.to_string(json_value),
      outgoing_payment.decode_grant_spent_amounts(),
    )
    == Ok(GrantSpentAmounts(
      spent_receive_amount: Some(Amount("100", "EUR", 2)),
      spent_debit_amount: None,
    ))
}
