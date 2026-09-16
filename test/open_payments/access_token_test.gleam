import gleam/json
import gleam/option.{Some}
import open_payments/access_token
import open_payments/types.{AccessQuote, AccessTokenResponse, QuoteCreate}

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
