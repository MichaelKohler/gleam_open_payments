import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import open_payments/error.{ApiError, TransportError, ValidationError}
import open_payments/grants.{
  type GrantResponse, AccessTokenBodyProperty, Body, ClientDirectedIdentity,
  ClientWalletAddressObject, ClientWalletAddressString, ContinueAccessToken,
  ContinueResponse, Finish, FinishRedirect, Grant, Interact, InteractResponse,
  PendingGrant, StartRedirect, Subject, SubjectId, SubjectIdFormatUri,
}
import open_payments/types.{
  type Access, AccessIncoming, AccessOutgoing, AccessQuote, AccessTokenResponse,
  IncomingCreate, IncomingRead, Key, OutgoingCreate, QuoteCreate, QuoteRead,
}
import support/mock_server
import support/test_client

pub fn encode_finish_test() {
  let finish = Finish(FinishRedirect, "https://example.com/finish", "nonce")

  assert json.to_string(grants.encode_finish(finish))
    == "{\"method\":\"redirect\",\"uri\":\"https://example.com/finish\",\"nonce\":\"nonce\"}"
}

pub fn encode_interact_with_finish_test() {
  let interact =
    Interact(
      start: [StartRedirect],
      finish: Some(Finish(FinishRedirect, "https://example.com/finish", "nonce")),
    )

  assert json.to_string(grants.encode_interact(interact))
    == "{\"finish\":{\"method\":\"redirect\",\"uri\":\"https://example.com/finish\",\"nonce\":\"nonce\"},\"start\":[\"redirect\"]}"
}

pub fn encode_interact_without_finish_test() {
  let interact = Interact(start: [StartRedirect], finish: None)

  assert json.to_string(grants.encode_interact(interact))
    == "{\"start\":[\"redirect\"]}"
}

pub fn encode_access_token_test() {
  let access_token = AccessTokenBodyProperty([AccessQuote([QuoteCreate])])

  assert json.to_string(grants.encode_access_token(access_token))
    == "{\"access\":[{\"type\":\"quote\",\"actions\":[\"create\"]}]}"
}

pub fn encode_access_token_multiple_access_test() {
  let access_token =
    AccessTokenBodyProperty([
      AccessQuote([QuoteCreate]),
      AccessIncoming(actions: [IncomingCreate], identifier: None),
    ])

  assert json.to_string(grants.encode_access_token(access_token))
    == "{\"access\":[{\"type\":\"quote\",\"actions\":[\"create\"]},{\"type\":\"incoming-payment\",\"actions\":[\"create\"]}]}"
}

pub fn encode_key_test() {
  let key = Key(kid: "key-1", x: "value")

  assert json.to_string(grants.encode_key(key))
    == "{\"kid\":\"key-1\",\"x\":\"value\",\"alg\":\"EdDSA\",\"kty\":\"OKP\",\"crv\":\"Ed25519\",\"use\":\"sig\"}"
}

pub fn encode_client_wallet_address_test() {
  let client = ClientWalletAddressObject("https://wallet.example/sender")

  assert json.to_string(grants.encode_client(client))
    == "{\"walletAddress\":\"https://wallet.example/sender\"}"
}

pub fn encode_client_wallet_address_string_test() {
  let client = ClientWalletAddressString("https://wallet.example/sender")

  assert json.to_string(grants.encode_client(client))
    == "\"https://wallet.example/sender\""
}

pub fn encode_client_directed_identity_test() {
  let key = Key(kid: "key-1", x: "value")
  let client = ClientDirectedIdentity(key)

  assert json.to_string(grants.encode_client(client))
    == "{\"jwk\":" <> json.to_string(grants.encode_key(key)) <> "}"
}

pub fn encode_body_test() {
  let body =
    Body(
      access_token: Some(AccessTokenBodyProperty([AccessQuote([QuoteCreate])])),
      client: ClientWalletAddressObject("https://wallet.example/sender"),
      interact: None,
      subject: None,
    )

  assert json.to_string(grants.encode_body(body))
    == "{\"access_token\":{\"access\":[{\"type\":\"quote\",\"actions\":[\"create\"]}]},\"client\":{\"walletAddress\":\"https://wallet.example/sender\"}}"
}

pub fn encode_body_with_subject_test() {
  let body =
    Body(
      access_token: None,
      client: ClientWalletAddressObject("https://wallet.example/sender"),
      interact: Some(Interact(start: [StartRedirect], finish: None)),
      subject: Some(SubjectId(
        id: "https://wallet.example/alice",
        format: SubjectIdFormatUri,
      )),
    )

  assert json.to_string(grants.encode_body(body))
    == "{\"subject\":{\"sub_ids\":[{\"id\":\"https://wallet.example/alice\",\"format\":\"uri\"}]},\"interact\":{\"start\":[\"redirect\"]},\"client\":{\"walletAddress\":\"https://wallet.example/sender\"}}"
}

pub fn encode_subject_test() {
  let subject =
    SubjectId(id: "https://wallet.example/alice", format: SubjectIdFormatUri)

  assert json.to_string(grants.encode_subject(subject))
    == "{\"sub_ids\":[{\"id\":\"https://wallet.example/alice\",\"format\":\"uri\"}]}"
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
  assert decoded.subject == None
}

pub fn decode_continuation_response_without_token_test() {
  let json_value = json.object([#("continue", continue_json())])

  let assert Ok(decoded) =
    json.parse(
      json.to_string(json_value),
      grants.decode_continuation_response(),
    )

  assert decoded.access_token == None
  assert decoded.subject == None
}

pub fn decode_continuation_response_with_subject_test() {
  let json_value =
    json.object([
      #(
        "subject",
        json.object([
          #(
            "sub_ids",
            json.array(
              [#("https://ilp.interledger-test.dev/alice", "uri")],
              fn(sub_id) {
                json.object([
                  #("id", json.string(sub_id.0)),
                  #("format", json.string(sub_id.1)),
                ])
              },
            ),
          ),
        ]),
      ),
      #("continue", continue_json()),
    ])

  let assert Ok(decoded) =
    json.parse(
      json.to_string(json_value),
      grants.decode_continuation_response(),
    )

  assert decoded.access_token == None
  assert decoded.subject
    == Some(
      Subject(sub_ids: [
        SubjectId(
          id: "https://ilp.interledger-test.dev/alice",
          format: SubjectIdFormatUri,
        ),
      ]),
    )
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

pub fn request_success_test() {
  let #(base_url, subject) =
    mock_server.start(
      status: 200,
      headers: [],
      body: json.to_string(
        json.object([
          #(
            "interact",
            json.object([
              #("redirect", json.string("https://auth.example/interact")),
            ]),
          ),
          #("continue", continue_json()),
        ]),
      ),
    )
  let client = test_client.client()
  let options =
    grants.GrantOptions(
      auth_server_url: base_url,
      access: [AccessQuote([QuoteCreate])],
      interact: None,
      address: "https://wallet.example/sender",
      client_type: None,
      subject: None,
    )

  let assert Ok(_) = grants.request(client, options)
  let captured = mock_server.await_request(subject)

  assert captured.method == "POST"
  assert list.key_find(captured.headers, "authorization") == Error(Nil)
  assert captured.body
    == json.to_string(
      json.object([
        #(
          "access_token",
          json.object([
            #(
              "access",
              json.array([AccessQuote([QuoteCreate])], types.encode_access),
            ),
          ]),
        ),
        #(
          "client",
          json.object([
            #(
              "walletAddress",
              json.string("https://ilp.interledger-test.dev/michaelusd"),
            ),
          ]),
        ),
      ]),
    )
}

pub fn request_directed_identity_with_interact_test() {
  let client = test_client.client()
  let key = Key(kid: "key-1", x: "value")
  let options =
    grants.GrantOptions(
      // Unreachable: the request must be rejected before anything is sent.
      auth_server_url: "http://127.0.0.1:1/unreachable",
      access: [AccessQuote([QuoteCreate])],
      interact: Some(Interact(start: [StartRedirect], finish: None)),
      address: "https://wallet.example/sender",
      client_type: Some(ClientDirectedIdentity(key)),
      subject: None,
    )

  assert grants.request(client, options)
    == Error(ValidationError(
      "A directed identity (jwk) client can only be used for non-interactive grants",
    ))
}

pub fn request_directed_identity_without_interact_test() {
  let #(base_url, mock_subject) =
    mock_server.start(
      status: 200,
      headers: [],
      body: json.to_string(
        json.object([
          #("access_token", access_token_json()),
          #("continue", continue_json()),
        ]),
      ),
    )
  let client = test_client.client()
  let key = Key(kid: "key-1", x: "value")
  let options =
    grants.GrantOptions(
      auth_server_url: base_url,
      access: [AccessQuote([QuoteCreate])],
      interact: None,
      address: "https://wallet.example/sender",
      client_type: Some(ClientDirectedIdentity(key)),
      subject: None,
    )

  let assert Ok(_) = grants.request(client, options)
  let captured = mock_server.await_request(mock_subject)

  assert string.contains(
    captured.body,
    "\"client\":{\"jwk\":" <> json.to_string(grants.encode_key(key)) <> "}",
  )
}

/// Requests a grant for `access` against an unreachable server, so that only
/// a request rejected before sending can return anything but a
/// `TransportError`.
fn request_unsent(access: List(Access)) {
  grants.request(
    test_client.client(),
    grants.GrantOptions(
      auth_server_url: "http://127.0.0.1:1/unreachable",
      access: access,
      interact: None,
      address: "https://wallet.example/sender",
      client_type: None,
      subject: None,
    ),
  )
}

pub fn request_without_access_or_subject_test() {
  assert request_unsent([])
    == Error(ValidationError(
      "A grant request requires at least one access item or a subject",
    ))
}

pub fn request_too_many_access_items_test() {
  assert request_unsent([
      AccessIncoming([IncomingCreate], None),
      AccessIncoming([IncomingRead], None),
      AccessQuote([QuoteCreate]),
      AccessQuote([QuoteRead]),
    ])
    == Error(ValidationError("A grant request may list at most 3 access items"))
}

pub fn request_duplicate_access_items_test() {
  assert request_unsent([
      AccessQuote([QuoteCreate]),
      AccessIncoming([IncomingCreate], None),
      AccessQuote([QuoteCreate]),
    ])
    == Error(ValidationError("A grant request's access items must be unique"))
}

pub fn request_duplicate_incoming_actions_test() {
  assert request_unsent([
      AccessIncoming([IncomingCreate, IncomingRead, IncomingCreate], None),
    ])
    == Error(ValidationError("An access item's actions must be unique"))
}

pub fn request_duplicate_outgoing_actions_test() {
  assert request_unsent([
      AccessOutgoing(
        [OutgoingCreate, OutgoingCreate],
        "https://wallet.example/sender",
        None,
      ),
    ])
    == Error(ValidationError("An access item's actions must be unique"))
}

pub fn request_duplicate_quote_actions_test() {
  assert request_unsent([AccessQuote([QuoteRead, QuoteRead])])
    == Error(ValidationError("An access item's actions must be unique"))
}

pub fn request_three_unique_access_items_is_sent_test() {
  let assert Error(TransportError(_)) =
    request_unsent([
      AccessIncoming([IncomingCreate, IncomingRead], None),
      AccessQuote([QuoteCreate, QuoteRead]),
      AccessOutgoing([OutgoingCreate], "https://wallet.example/sender", None),
    ])
}

pub fn request_with_subject_without_interact_test() {
  let client = test_client.client()
  let options =
    grants.GrantOptions(
      // Unreachable: the request must be rejected before anything is sent.
      auth_server_url: "http://127.0.0.1:1/unreachable",
      access: [],
      interact: None,
      address: "https://wallet.example/sender",
      client_type: None,
      subject: Some(SubjectId(
        id: "https://wallet.example/alice",
        format: SubjectIdFormatUri,
      )),
    )

  assert grants.request(client, options)
    == Error(ValidationError("A grant request with a subject requires interact"))
}

pub fn request_with_subject_success_test() {
  let #(base_url, mock_subject) =
    mock_server.start(
      status: 200,
      headers: [],
      body: json.to_string(
        json.object([
          #(
            "interact",
            json.object([
              #("redirect", json.string("https://auth.example/interact")),
            ]),
          ),
          #("continue", continue_json()),
        ]),
      ),
    )
  let client = test_client.client()
  let options =
    grants.GrantOptions(
      auth_server_url: base_url,
      access: [],
      interact: Some(Interact(start: [StartRedirect], finish: None)),
      address: "https://wallet.example/sender",
      client_type: None,
      subject: Some(SubjectId(
        id: "https://ilp.interledger-test.dev/michaelusd",
        format: SubjectIdFormatUri,
      )),
    )

  let assert Ok(_) = grants.request(client, options)
  let captured = mock_server.await_request(mock_subject)

  assert captured.body
    == json.to_string(
      json.object([
        #(
          "subject",
          json.object([
            #(
              "sub_ids",
              json.array(
                [
                  SubjectId(
                    id: "https://ilp.interledger-test.dev/michaelusd",
                    format: SubjectIdFormatUri,
                  ),
                ],
                grants.encode_subject_id,
              ),
            ),
          ]),
        ),
        #(
          "interact",
          json.object([#("start", json.array(["redirect"], json.string))]),
        ),
        #(
          "client",
          json.object([
            #(
              "walletAddress",
              json.string("https://ilp.interledger-test.dev/michaelusd"),
            ),
          ]),
        ),
      ]),
    )
}

pub fn request_error_status_test() {
  let #(base_url, _subject) =
    mock_server.start(status: 404, headers: [], body: "not found")
  let client = test_client.client()
  let options =
    grants.GrantOptions(
      auth_server_url: base_url,
      access: [AccessQuote([QuoteCreate])],
      interact: None,
      address: "https://wallet.example/sender",
      client_type: None,
      subject: None,
    )

  assert grants.request(client, options)
    == Error(ApiError(status: 404, body: "not found", error: None, as_uri: None))
}

pub fn continue_success_test() {
  let #(base_url, subject) =
    mock_server.start(
      status: 200,
      headers: [],
      body: json.to_string(json.object([#("continue", continue_json())])),
    )
  let client = test_client.client()
  let response =
    ContinueResponse(
      access_token: ContinueAccessToken("continue-access-token"),
      uri: base_url,
      wait: None,
    )

  let assert Ok(_) =
    grants.continue(client, response, Some("interact-ref-value"))
  let captured = mock_server.await_request(subject)

  assert captured.method == "POST"
  assert captured.body == "{\"interact_ref\":\"interact-ref-value\"}"
  assert list.key_find(captured.headers, "authorization")
    == Ok("GNAP continue-access-token")
}

pub fn continue_without_interact_ref_test() {
  let #(base_url, subject) =
    mock_server.start(
      status: 200,
      headers: [],
      body: json.to_string(json.object([#("continue", continue_json())])),
    )
  let client = test_client.client()
  let response =
    ContinueResponse(
      access_token: ContinueAccessToken("continue-access-token"),
      uri: base_url,
      wait: None,
    )

  let assert Ok(_) = grants.continue(client, response, None)
  let captured = mock_server.await_request(subject)

  assert captured.method == "POST"
  assert captured.body == ""
  assert list.key_find(captured.headers, "content-digest") == Error(Nil)
  assert list.key_find(captured.headers, "authorization")
    == Ok("GNAP continue-access-token")
}

pub fn continue_error_status_test() {
  let #(base_url, _subject) =
    mock_server.start(status: 404, headers: [], body: "not found")
  let client = test_client.client()
  let response =
    ContinueResponse(
      access_token: ContinueAccessToken("continue-access-token"),
      uri: base_url,
      wait: None,
    )

  assert grants.continue(client, response, Some("interact-ref-value"))
    == Error(ApiError(status: 404, body: "not found", error: None, as_uri: None))
}

pub fn cancel_success_test() {
  let #(base_url, subject) =
    mock_server.start(status: 204, headers: [], body: "")
  let client = test_client.client()
  let response =
    ContinueResponse(
      access_token: ContinueAccessToken("continue-access-token"),
      uri: base_url,
      wait: None,
    )

  assert grants.cancel(client, response) == Ok(Nil)

  let captured = mock_server.await_request(subject)
  assert captured.method == "DELETE"
  assert list.key_find(captured.headers, "authorization")
    == Ok("GNAP continue-access-token")
}

pub fn cancel_error_status_test() {
  let #(base_url, _subject) =
    mock_server.start(status: 404, headers: [], body: "not found")
  let client = test_client.client()
  let response =
    ContinueResponse(
      access_token: ContinueAccessToken("continue-access-token"),
      uri: base_url,
      wait: None,
    )

  assert grants.cancel(client, response)
    == Error(ApiError(status: 404, body: "not found", error: None, as_uri: None))
}
