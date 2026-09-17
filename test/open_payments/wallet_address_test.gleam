import gleam/json
import gleam/list
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
      public_name: "Alice",
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
    == Ok(Key(
      kid: "key-1",
      x: "base64url-value",
      alg: "EdDSA",
      kty: "OKP",
      crv: "Ed25519",
      use_: "sig",
    ))
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
    == Ok(Key(
      kid: "key-1",
      x: "base64url-value",
      alg: "EdDSA",
      kty: "OKP",
      crv: "Ed25519",
      use_: "sig",
    ))
}

pub fn decode_keys_test() {
  let key =
    Key(
      kid: "key-1",
      x: "value",
      alg: "EdDSA",
      kty: "OKP",
      crv: "Ed25519",
      use_: "sig",
    )
  let json_value =
    json.object([
      #(
        "keys",
        json.array([key], fn(k) {
          json.object([
            #("kid", json.string(k.kid)),
            #("x", json.string(k.x)),
            #("alg", json.string(k.alg)),
            #("kty", json.string(k.kty)),
            #("crv", json.string(k.crv)),
            #("use", json.string(k.use_)),
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
    == Error(ApiError(status: 404, body: "not found"))
}

pub fn get_keys_success_test() {
  let #(base_url, subject) =
    mock_server.start(status: 200, headers: [], body: "{\"keys\":[]}")

  let assert Ok(_) = wallet_address.get_keys(base_url)
  let captured = mock_server.await_request(subject)

  assert captured.method == "GET"
  assert captured.path == "/jwks.json"
}

pub fn get_keys_error_status_test() {
  let #(base_url, _subject) =
    mock_server.start(status: 404, headers: [], body: "not found")

  assert wallet_address.get_keys(base_url)
    == Error(ApiError(status: 404, body: "not found"))
}
