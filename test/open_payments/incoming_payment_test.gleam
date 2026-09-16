import gleam/json
import gleam/option.{None, Some}
import open_payments/incoming_payment.{
  CreateOptions, IlpPaymentMethod, IncomingPayment,
}
import open_payments/types.{Amount}

pub fn encode_create_body_test() {
  let options =
    CreateOptions(
      resource_server: "https://resource.example",
      wallet_address: "https://wallet.example/receiver",
      incoming_amount: Some(Amount("1000", "USD", 2)),
      expires_at: Some("2024-01-01T00:05:00Z"),
      metadata: None,
    )

  assert json.to_string(incoming_payment.encode_create_body(options))
    == "{\"expiresAt\":\"2024-01-01T00:05:00Z\",\"incomingAmount\":{\"value\":\"1000\",\"assetCode\":\"USD\",\"assetScale\":2},\"walletAddress\":\"https://wallet.example/receiver\"}"
}

pub fn encode_create_body_minimal_test() {
  let options =
    CreateOptions(
      resource_server: "https://resource.example",
      wallet_address: "https://wallet.example/receiver",
      incoming_amount: None,
      expires_at: None,
      metadata: None,
    )

  assert json.to_string(incoming_payment.encode_create_body(options))
    == "{\"walletAddress\":\"https://wallet.example/receiver\"}"
}

pub fn decode_ilp_payment_method_test() {
  let json_value =
    json.object([
      #("ilpAddress", json.string("g.example.receiver")),
      #("sharedSecret", json.string("shared-secret")),
    ])

  assert json.parse(
      json.to_string(json_value),
      incoming_payment.decode_ilp_payment_method(),
    )
    == Ok(IlpPaymentMethod(
      ilp_address: "g.example.receiver",
      shared_secret: "shared-secret",
    ))
}

pub fn decode_incoming_payment_test() {
  let json_value =
    json.object([
      #("id", json.string("https://resource.example/incoming-payments/1")),
      #("walletAddress", json.string("https://wallet.example/receiver")),
      #("completed", json.bool(False)),
      #("incomingAmount", types.encode_amount(Amount("1000", "USD", 2))),
      #("receivedAmount", types.encode_amount(Amount("0", "USD", 2))),
      #("expiresAt", json.string("2024-01-01T00:05:00Z")),
      #("createdAt", json.string("2024-01-01T00:00:00Z")),
      #(
        "methods",
        json.array(
          [IlpPaymentMethod("g.example.receiver", "shared-secret")],
          fn(m) {
            json.object([
              #("ilpAddress", json.string(m.ilp_address)),
              #("sharedSecret", json.string(m.shared_secret)),
            ])
          },
        ),
      ),
    ])

  assert json.parse(
      json.to_string(json_value),
      incoming_payment.decode_incoming_payment(),
    )
    == Ok(
      IncomingPayment(
        id: "https://resource.example/incoming-payments/1",
        wallet_address: "https://wallet.example/receiver",
        completed: False,
        incoming_amount: Some(Amount("1000", "USD", 2)),
        received_amount: Amount("0", "USD", 2),
        expires_at: Some("2024-01-01T00:05:00Z"),
        metadata: None,
        created_at: "2024-01-01T00:00:00Z",
        methods: [IlpPaymentMethod("g.example.receiver", "shared-secret")],
      ),
    )
}

pub fn decode_incoming_payment_defaults_test() {
  let json_value =
    json.object([
      #("id", json.string("https://resource.example/incoming-payments/1")),
      #("walletAddress", json.string("https://wallet.example/receiver")),
      #("completed", json.bool(True)),
      #("receivedAmount", types.encode_amount(Amount("1000", "USD", 2))),
      #("createdAt", json.string("2024-01-01T00:00:00Z")),
    ])

  assert json.parse(
      json.to_string(json_value),
      incoming_payment.decode_incoming_payment(),
    )
    == Ok(
      IncomingPayment(
        id: "https://resource.example/incoming-payments/1",
        wallet_address: "https://wallet.example/receiver",
        completed: True,
        incoming_amount: None,
        received_amount: Amount("1000", "USD", 2),
        expires_at: None,
        metadata: None,
        created_at: "2024-01-01T00:00:00Z",
        methods: [],
      ),
    )
}

pub fn decode_incoming_payment_list_test() {
  let payment =
    IncomingPayment(
      id: "https://resource.example/incoming-payments/1",
      wallet_address: "https://wallet.example/receiver",
      completed: True,
      incoming_amount: None,
      received_amount: Amount("1000", "USD", 2),
      expires_at: None,
      metadata: None,
      created_at: "2024-01-01T00:00:00Z",
      methods: [],
    )

  let json_value =
    json.object([
      #(
        "pagination",
        json.object([
          #("hasNextPage", json.bool(False)),
          #("hasPreviousPage", json.bool(False)),
        ]),
      ),
      #(
        "result",
        json.array([payment], fn(p) {
          json.object([
            #("id", json.string(p.id)),
            #("walletAddress", json.string(p.wallet_address)),
            #("completed", json.bool(p.completed)),
            #("receivedAmount", types.encode_amount(p.received_amount)),
            #("createdAt", json.string(p.created_at)),
          ])
        }),
      ),
    ])

  let assert Ok(decoded) =
    json.parse(
      json.to_string(json_value),
      incoming_payment.decode_incoming_payment_list(),
    )

  assert decoded.result == [payment]
  assert decoded.pagination.has_next_page == False
}
