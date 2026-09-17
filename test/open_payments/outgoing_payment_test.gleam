import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import open_payments/error.{ApiError}
import open_payments/outgoing_payment.{
  CreateOptions, FromIncomingPayment, FromQuote, GrantSpentAmounts, ListOptions,
  OutgoingPayment,
}
import open_payments/types.{Amount}
import support/mock_server
import support/test_client

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

fn outgoing_payment_json() -> String {
  "{\"id\":\"https://resource.example/outgoing-payments/1\",\"walletAddress\":\"https://wallet.example/sender\",\"receiver\":\"https://resource.example/incoming-payments/1\",\"receiveAmount\":{\"value\":\"480\",\"assetCode\":\"EUR\",\"assetScale\":2},\"debitAmount\":{\"value\":\"500\",\"assetCode\":\"USD\",\"assetScale\":2},\"sentAmount\":{\"value\":\"0\",\"assetCode\":\"USD\",\"assetScale\":2},\"createdAt\":\"2024-01-01T00:00:00Z\"}"
}

pub fn create_success_test() {
  let #(base_url, subject) =
    mock_server.start(status: 201, headers: [], body: outgoing_payment_json())
  let client = test_client.client()
  let options =
    CreateOptions(
      resource_server: base_url,
      wallet_address: "https://wallet.example/sender",
      source: FromQuote("https://resource.example/quotes/1"),
      metadata: None,
    )

  let assert Ok(_) = outgoing_payment.create(client, "access-token", options)
  let captured = mock_server.await_request(subject)

  assert captured.method == "POST"
  assert captured.path == "/outgoing-payments"
  assert list.key_find(captured.headers, "authorization")
    == Ok("GNAP access-token")
  assert captured.body
    == json.to_string(outgoing_payment.encode_create_body(options))
}

pub fn create_error_status_test() {
  let #(base_url, _subject) =
    mock_server.start(status: 404, headers: [], body: "not found")
  let client = test_client.client()
  let options =
    CreateOptions(
      resource_server: base_url,
      wallet_address: "https://wallet.example/sender",
      source: FromQuote("https://resource.example/quotes/1"),
      metadata: None,
    )

  assert outgoing_payment.create(client, "access-token", options)
    == Error(ApiError(status: 404, body: "not found"))
}

pub fn list_success_test() {
  let #(base_url, subject) =
    mock_server.start(
      status: 200,
      headers: [],
      body: "{\"pagination\":{\"hasNextPage\":false,\"hasPreviousPage\":false},\"result\":[]}",
    )
  let client = test_client.client()
  let options =
    ListOptions(
      resource_server: base_url,
      wallet_address: "https://wallet.example/sender",
      cursor: None,
      first: Some(5),
      last: None,
    )

  let assert Ok(_) = outgoing_payment.list(client, "access-token", options)
  let captured = mock_server.await_request(subject)

  assert captured.method == "GET"
  assert string.starts_with(captured.path, "/outgoing-payments?")
  assert string.contains(captured.path, "first=5")
}

pub fn list_error_status_test() {
  let #(base_url, _subject) =
    mock_server.start(status: 404, headers: [], body: "not found")
  let client = test_client.client()
  let options =
    ListOptions(
      resource_server: base_url,
      wallet_address: "https://wallet.example/sender",
      cursor: None,
      first: None,
      last: None,
    )

  assert outgoing_payment.list(client, "access-token", options)
    == Error(ApiError(status: 404, body: "not found"))
}

pub fn get_success_test() {
  let #(base_url, subject) =
    mock_server.start(status: 200, headers: [], body: outgoing_payment_json())
  let client = test_client.client()

  let assert Ok(_) =
    outgoing_payment.get(
      client,
      "access-token",
      base_url <> "/outgoing-payments/1",
    )
  let captured = mock_server.await_request(subject)

  assert captured.method == "GET"
  assert captured.path == "/outgoing-payments/1"
}

pub fn get_error_status_test() {
  let #(base_url, _subject) =
    mock_server.start(status: 404, headers: [], body: "not found")
  let client = test_client.client()

  assert outgoing_payment.get(
      client,
      "access-token",
      base_url <> "/outgoing-payments/1",
    )
    == Error(ApiError(status: 404, body: "not found"))
}

pub fn get_grant_spent_amounts_success_test() {
  let #(base_url, subject) =
    mock_server.start(
      status: 200,
      headers: [],
      body: "{\"spentReceiveAmount\":null,\"spentDebitAmount\":null}",
    )
  let client = test_client.client()

  let assert Ok(_) =
    outgoing_payment.get_grant_spent_amounts(client, "access-token", base_url)
  let captured = mock_server.await_request(subject)

  assert captured.method == "GET"
  assert captured.path == "/outgoing-payment-grant"
}

pub fn get_grant_spent_amounts_error_status_test() {
  let #(base_url, _subject) =
    mock_server.start(status: 404, headers: [], body: "not found")
  let client = test_client.client()

  assert outgoing_payment.get_grant_spent_amounts(
      client,
      "access-token",
      base_url,
    )
    == Error(ApiError(status: 404, body: "not found"))
}
