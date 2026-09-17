import gleam/json
import gleam/list
import gleam/option.{None, Some}
import open_payments/access_token
import open_payments/error.{ApiError}
import open_payments/types.{
  type AccessTokenResponse, AccessQuote, AccessTokenResponse, QuoteCreate,
}
import support/mock_server
import support/test_client

pub fn decode_rotate_response_test() {
  let json_value =
    json.object([
      #(
        "access_token",
        json.object([
          #("value", json.string("token-value")),
          #("manage", json.string("https://auth.example/token/abc")),
          #("expires_in", json.int(3600)),
          #(
            "access",
            json.array([AccessQuote([QuoteCreate])], types.encode_access),
          ),
        ]),
      ),
    ])

  assert json.parse(
      json.to_string(json_value),
      access_token.decode_rotate_response(),
    )
    == Ok(
      AccessTokenResponse(
        value: "token-value",
        manage: "https://auth.example/token/abc",
        expires_in: Some(3600),
        access: [AccessQuote([QuoteCreate])],
      ),
    )
}

fn access_token(manage manage: String) -> AccessTokenResponse {
  AccessTokenResponse(
    value: "token-value",
    manage: manage,
    expires_in: None,
    access: [AccessQuote([QuoteCreate])],
  )
}

pub fn rotate_success_test() {
  let #(base_url, subject) =
    mock_server.start(
      status: 200,
      headers: [],
      body: "{\"access_token\":{\"value\":\"new-token\",\"manage\":\"https://auth.example/token/abc\",\"access\":[]}}",
    )
  let client = test_client.client()

  let assert Ok(_) = access_token.rotate(client, access_token(manage: base_url))
  let captured = mock_server.await_request(subject)

  assert captured.method == "POST"
  assert list.key_find(captured.headers, "authorization")
    == Ok("GNAP token-value")
}

pub fn rotate_error_status_test() {
  let #(base_url, _subject) =
    mock_server.start(status: 404, headers: [], body: "not found")
  let client = test_client.client()

  assert access_token.rotate(client, access_token(manage: base_url))
    == Error(ApiError(status: 404, body: "not found"))
}

pub fn revoke_success_test() {
  let #(base_url, subject) =
    mock_server.start(status: 204, headers: [], body: "")
  let client = test_client.client()

  assert access_token.revoke(client, access_token(manage: base_url)) == Ok(Nil)

  let captured = mock_server.await_request(subject)
  assert captured.method == "DELETE"
  assert list.key_find(captured.headers, "authorization")
    == Ok("GNAP token-value")
}

pub fn revoke_error_status_test() {
  let #(base_url, _subject) =
    mock_server.start(status: 404, headers: [], body: "not found")
  let client = test_client.client()

  assert access_token.revoke(client, access_token(manage: base_url))
    == Error(ApiError(status: 404, body: "not found"))
}
