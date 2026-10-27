import gleam/json
import gleam/list
import gleam/option.{None, Some}
import open_payments/error.{ApiError}
import open_payments/types.{Key}
import open_payments/wallet_address.{WalletInfo}
import support/mock_server

pub fn decode_wallet_info_test() {
  let json_value =
    json.object([
      #("id", json.string("https://wallet.example/alice")),
      #("publicName", json.string("Alice")),
      #("assetCode", json.string("USD")),
      #("assetScale", json.int(2)),
      #("authServer", json.string("https://auth.example")),
      #("resourceServer", json.string("https://resource.example")),
    ])

  assert json.parse(
      json.to_string(json_value),
      wallet_address.decode_wallet_info(),
    )
    == Ok(WalletInfo(
      id: "https://wallet.example/alice",
      public_name: Some("Alice"),
      asset_code: "USD",
      asset_scale: 2,
      auth_server: "https://auth.example",
      resource_server: "https://resource.example",
    ))
}

pub fn decode_wallet_info_without_public_name_test() {
  let json_value =
    json.object([
      #("id", json.string("https://wallet.example/alice")),
      #("assetCode", json.string("USD")),
      #("assetScale", json.int(2)),
      #("authServer", json.string("https://auth.example")),
      #("resourceServer", json.string("https://resource.example")),
    ])

  assert json.parse(
      json.to_string(json_value),
      wallet_address.decode_wallet_info(),
    )
    == Ok(WalletInfo(
      id: "https://wallet.example/alice",
      public_name: None,
      asset_code: "USD",
      asset_scale: 2,
      auth_server: "https://auth.example",
      resource_server: "https://resource.example",
    ))
}

pub fn decode_key_test() {
  let json_value =
    json.object([
      #("kid", json.string("key-1")),
      #("x", json.string("base64url-value")),
      #("alg", json.string("EdDSA")),
      #("kty", json.string("OKP")),
      #("crv", json.string("Ed25519")),
      #("use", json.string("sig")),
    ])

  assert json.parse(json.to_string(json_value), wallet_address.decode_key())
    == Ok(Key(kid: "key-1", x: "base64url-value"))
}

pub fn decode_key_without_use_test() {
  let json_value =
    json.object([
      #("kid", json.string("key-1")),
      #("x", json.string("base64url-value")),
      #("alg", json.string("EdDSA")),
      #("kty", json.string("OKP")),
      #("crv", json.string("Ed25519")),
    ])

  assert json.parse(json.to_string(json_value), wallet_address.decode_key())
    == Ok(Key(kid: "key-1", x: "base64url-value"))
}

pub fn decode_key_rejects_other_key_types_test() {
  let key_json = fn(field, value) {
    [
      #("kid", json.string("key-1")),
      #("x", json.string("base64url-value")),
      #("alg", json.string("EdDSA")),
      #("kty", json.string("OKP")),
      #("crv", json.string("Ed25519")),
      #("use", json.string("sig")),
    ]
    |> list.key_set(field, json.string(value))
    |> json.object
    |> json.to_string
  }

  let assert Error(_) =
    json.parse(key_json("alg", "ES256"), wallet_address.decode_key())
  let assert Error(_) =
    json.parse(key_json("kty", "EC"), wallet_address.decode_key())
  let assert Error(_) =
    json.parse(key_json("crv", "X25519"), wallet_address.decode_key())
  let assert Error(_) =
    json.parse(key_json("use", "enc"), wallet_address.decode_key())
}

pub fn decode_keys_test() {
  let key = Key(kid: "key-1", x: "value")
  let json_value =
    json.object([
      #(
        "keys",
        json.array([key], fn(k) {
          json.object([
            #("kid", json.string(k.kid)),
            #("x", json.string(k.x)),
            #("alg", json.string("EdDSA")),
            #("kty", json.string("OKP")),
            #("crv", json.string("Ed25519")),
            #("use", json.string("sig")),
          ])
        }),
      ),
    ])

  assert json.parse(json.to_string(json_value), wallet_address.decode_keys())
    == Ok([key])
}

pub fn get_success_test() {
  let #(base_url, subject) =
    mock_server.start(
      status: 200,
      headers: [],
      body: "{\"id\":\"https://wallet.example/alice\",\"publicName\":\"Alice\",\"assetCode\":\"USD\",\"assetScale\":2,\"authServer\":\"https://auth.example\",\"resourceServer\":\"https://resource.example\"}",
    )

  let assert Ok(_) = wallet_address.get(base_url)
  let captured = mock_server.await_request(subject)

  assert captured.method == "GET"
  assert captured.path == "/"
  assert list.key_find(captured.headers, "authorization") == Error(Nil)
}

pub fn get_error_status_test() {
  let #(base_url, _subject) =
    mock_server.start(status: 404, headers: [], body: "not found")

  assert wallet_address.get(base_url)
    == Error(ApiError(status: 404, body: "not found", error: None, as_uri: None))
}

pub fn get_keys_success_test() {
  let #(base_url, subject) =
    mock_server.start(status: 200, headers: [], body: "{\"keys\":[]}")

  let assert Ok(_) = wallet_address.get_keys(base_url)
  let captured = mock_server.await_request(subject)

  assert captured.method == "GET"
  assert captured.path == "/jwks.json"
}

pub fn decode_keys_skips_unusable_keys_test() {
  let ed25519_key = fn(kid) {
    json.object([
      #("kid", json.string(kid)),
      #("x", json.string("value")),
      #("alg", json.string("EdDSA")),
      #("kty", json.string("OKP")),
      #("crv", json.string("Ed25519")),
    ])
  }
  let json_value =
    json.object([
      #(
        "keys",
        json.preprocessed_array([
          ed25519_key("old-key"),
          // A P-256 key, as might be listed during a key migration.
          json.object([
            #("kid", json.string("ec-key")),
            #("kty", json.string("EC")),
            #("crv", json.string("P-256")),
            #("alg", json.string("ES256")),
            #("x", json.string("x-value")),
            #("y", json.string("y-value")),
          ]),
          // An Ed25519 key marked for encryption rather than signing.
          json.object([
            #("kid", json.string("enc-key")),
            #("x", json.string("value")),
            #("alg", json.string("EdDSA")),
            #("kty", json.string("OKP")),
            #("crv", json.string("Ed25519")),
            #("use", json.string("enc")),
          ]),
          json.string("not a key"),
          ed25519_key("new-key"),
        ]),
      ),
    ])

  assert json.parse(json.to_string(json_value), wallet_address.decode_keys())
    == Ok([Key(kid: "old-key", x: "value"), Key(kid: "new-key", x: "value")])
}

pub fn decode_keys_requires_keys_list_test() {
  let assert Error(_) =
    json.parse("{\"keys\":\"nope\"}", wallet_address.decode_keys())
  let assert Error(_) = json.parse("{}", wallet_address.decode_keys())
}

pub fn get_keys_error_status_test() {
  let #(base_url, _subject) =
    mock_server.start(status: 404, headers: [], body: "not found")

  assert wallet_address.get_keys(base_url)
    == Error(ApiError(status: 404, body: "not found", error: None, as_uri: None))
}
