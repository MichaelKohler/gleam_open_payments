import gleam/json
import gleam/option.{None, Some}
import open_payments/grants.{
  type GrantResponse, AccessTokenBodyProperty, Body, ClientDirectedIdentity,
  ClientWalletAddressObject, ContinueAccessToken, ContinueResponse, Finish,
  Grant, Interact, InteractResponse, PendingGrant,
}
import open_payments/types.{AccessQuote, AccessTokenResponse, Key, QuoteCreate}

pub fn encode_finish_test() {
  let finish = Finish("redirect", "https://example.com/finish", "nonce")

  assert json.to_string(grants.encode_finish(finish))
    == "{\"method\":\"redirect\",\"uri\":\"https://example.com/finish\",\"nonce\":\"nonce\"}"
}

pub fn encode_interact_with_finish_test() {
  let interact =
    Interact(
      start: ["redirect"],
      finish: Some(Finish("redirect", "https://example.com/finish", "nonce")),
    )

  assert json.to_string(grants.encode_interact(interact))
    == "{\"finish\":{\"method\":\"redirect\",\"uri\":\"https://example.com/finish\",\"nonce\":\"nonce\"},\"start\":[\"redirect\"]}"
}

pub fn encode_interact_without_finish_test() {
  let interact = Interact(start: ["redirect"], finish: None)

  assert json.to_string(grants.encode_interact(interact))
    == "{\"start\":[\"redirect\"]}"
}

pub fn encode_access_token_test() {
  let access_token = AccessTokenBodyProperty(AccessQuote([QuoteCreate]))

  assert json.to_string(grants.encode_access_token(access_token))
    == "{\"access\":[{\"type\":\"quote\",\"actions\":[\"create\"]}]}"
}

pub fn encode_key_test() {
  let key =
    Key(kid: "key-1", x: "value", alg: "EdDSA", kty: "OKP", crv: "Ed25519")

  assert json.to_string(grants.encode_key(key))
    == "{\"kid\":\"key-1\",\"x\":\"value\",\"alg\":\"EdDSA\",\"kty\":\"OKP\",\"crv\":\"Ed25519\"}"
}

pub fn encode_client_wallet_address_test() {
  let client = ClientWalletAddressObject("https://wallet.example/sender")

  assert json.to_string(grants.encode_client(client))
    == "\"https://wallet.example/sender\""
}

pub fn encode_client_directed_identity_test() {
  let key =
    Key(kid: "key-1", x: "value", alg: "EdDSA", kty: "OKP", crv: "Ed25519")
  let client = ClientDirectedIdentity(key)

  assert json.to_string(grants.encode_client(client))
    == json.to_string(grants.encode_key(key))
}

pub fn encode_body_test() {
  let body =
    Body(
      access_token: AccessTokenBodyProperty(AccessQuote([QuoteCreate])),
      client: ClientWalletAddressObject("https://wallet.example/sender"),
      interact: None,
    )

  assert json.to_string(grants.encode_body(body))
    == "{\"access_token\":{\"access\":[{\"type\":\"quote\",\"actions\":[\"create\"]}]},\"client\":\"https://wallet.example/sender\"}"
}

pub fn decode_interact_response_test() {
  let json_value =
    json.object([
      #("redirect", json.string("https://auth.example/interact")),
      #("finish", json.string("finish-nonce")),
    ])

  assert json.parse(
      json.to_string(json_value),
      grants.decode_interact_response(),
    )
    == Ok(InteractResponse(
      redirect: "https://auth.example/interact",
      finish: Some("finish-nonce"),
    ))
}

pub fn decode_continue_response_test() {
  let json_value =
    json.object([
      #(
        "access_token",
        json.object([#("value", json.string("continue-token"))]),
      ),
      #("uri", json.string("https://auth.example/continue")),
      #("wait", json.int(5)),
    ])

  assert json.parse(
      json.to_string(json_value),
      grants.decode_continue_response(),
    )
    == Ok(ContinueResponse(
      access_token: ContinueAccessToken("continue-token"),
      uri: "https://auth.example/continue",
      wait: Some(5),
    ))
}

fn access_token_json() -> json.Json {
  json.object([
    #("value", json.string("token-value")),
    #("manage", json.string("https://auth.example/token/abc")),
    #("access", json.array([AccessQuote([QuoteCreate])], types.encode_access)),
  ])
}

fn continue_json() -> json.Json {
  json.object([
    #("access_token", json.object([#("value", json.string("continue-token"))])),
    #("uri", json.string("https://auth.example/continue")),
  ])
}

pub fn decode_grant_response_pending_test() {
  let json_value =
    json.object([
      #(
        "interact",
        json.object([
          #("redirect", json.string("https://auth.example/interact")),
        ]),
      ),
      #("continue", continue_json()),
    ])

  assert json.parse(json.to_string(json_value), grants.decode_grant_response())
    == Ok(PendingGrant(
      interact: InteractResponse(
        redirect: "https://auth.example/interact",
        finish: None,
      ),
      continue: ContinueResponse(
        access_token: ContinueAccessToken("continue-token"),
        uri: "https://auth.example/continue",
        wait: None,
      ),
    ))
}

pub fn decode_grant_response_grant_test() {
  let json_value =
    json.object([
      #("access_token", access_token_json()),
      #("continue", continue_json()),
    ])

  assert json.parse(json.to_string(json_value), grants.decode_grant_response())
    == Ok(Grant(
      access_token: AccessTokenResponse(
        value: "token-value",
        manage: "https://auth.example/token/abc",
        expires_in: None,
        access: [AccessQuote([QuoteCreate])],
      ),
      continue: ContinueResponse(
        access_token: ContinueAccessToken("continue-token"),
        uri: "https://auth.example/continue",
        wait: None,
      ),
    ))
}

pub fn encode_continue_body_test() {
  assert json.to_string(grants.encode_continue_body("interact-ref"))
    == "{\"interact_ref\":\"interact-ref\"}"
}

pub fn decode_continuation_response_with_token_test() {
  let json_value =
    json.object([
      #("access_token", access_token_json()),
      #("continue", continue_json()),
    ])

  let assert Ok(decoded) =
    json.parse(
      json.to_string(json_value),
      grants.decode_continuation_response(),
    )

  assert decoded.access_token
    == Some(
      AccessTokenResponse(
        value: "token-value",
        manage: "https://auth.example/token/abc",
        expires_in: None,
        access: [AccessQuote([QuoteCreate])],
      ),
    )
}

pub fn decode_continuation_response_without_token_test() {
  let json_value = json.object([#("continue", continue_json())])

  let assert Ok(decoded) =
    json.parse(
      json.to_string(json_value),
      grants.decode_continuation_response(),
    )

  assert decoded.access_token == None
}

pub fn is_interactive_grant_pending_test() {
  let grant: GrantResponse =
    PendingGrant(
      interact: InteractResponse(redirect: "https://example.com", finish: None),
      continue: ContinueResponse(
        access_token: ContinueAccessToken("token"),
        uri: "https://example.com/continue",
        wait: None,
      ),
    )

  assert grants.is_interactive_grant(grant) == True
}

pub fn is_interactive_grant_grant_test() {
  let grant: GrantResponse =
    Grant(
      access_token: AccessTokenResponse(
        value: "token-value",
        manage: "https://auth.example/token/abc",
        expires_in: None,
        access: [],
      ),
      continue: ContinueResponse(
        access_token: ContinueAccessToken("token"),
        uri: "https://example.com/continue",
        wait: None,
      ),
    )

  assert grants.is_interactive_grant(grant) == False
}
