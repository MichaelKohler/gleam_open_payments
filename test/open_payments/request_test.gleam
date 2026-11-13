import gleam/dynamic/decode
import gleam/http
import gleam/http/response.{Response}
import gleam/httpc
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/time/timestamp
import http_digest_fields/content_digest
import http_message_signatures/component.{
  type ComponentIdentifier, Derived, Field, Method, TargetUri,
}
import http_message_signatures/keys
import http_message_signatures/message
import http_message_signatures/verifier.{type VerifyError, VerifyPolicy}
import open_payments/error.{
  ApiError, DecodeError, InvalidClient, ServerError, TransportError,
}
import open_payments/request
import simplifile
import support/mock_server.{type CapturedRequest}
import support/test_client

const unreachable_url = "http://127.0.0.1:1/unreachable"

pub fn handle_response_ok_test() {
  let resp = Ok(Response(status: 200, headers: [], body: "{\"ok\":true}"))

  assert request.handle_response(resp) == Ok("{\"ok\":true}")
}

pub fn handle_response_created_test() {
  let resp = Ok(Response(status: 201, headers: [], body: "created"))

  assert request.handle_response(resp) == Ok("created")
}

pub fn handle_response_no_content_test() {
  let resp = Ok(Response(status: 204, headers: [], body: ""))

  assert request.handle_response(resp) == Ok("")
}

pub fn handle_response_accepted_test() {
  let resp = Ok(Response(status: 202, headers: [], body: "accepted"))

  assert request.handle_response(resp) == Ok("accepted")
}

pub fn handle_response_redirect_status_test() {
  let resp = Ok(Response(status: 302, headers: [], body: ""))

  assert request.handle_response(resp)
    == Error(ApiError(status: 302, body: "", error: None, as_uri: None))
}

pub fn handle_response_error_status_test() {
  let resp = Ok(Response(status: 404, headers: [], body: "not found"))

  assert request.handle_response(resp)
    == Error(ApiError(status: 404, body: "not found", error: None, as_uri: None))
}

pub fn handle_response_transport_error_test() {
  let resp = Error(httpc.InvalidUtf8Response)

  assert request.handle_response(resp)
    == Error(TransportError("Request failed: InvalidUtf8Response"))
}

pub fn send_unauthenticated_request_success_test() {
  let #(base_url, subject) =
    mock_server.start(status: 200, headers: [], body: "{\"ok\":true}")

  let assert Ok(body) =
    request.send_unauthenticated_request(base_url <> "/wallet")
  let captured = mock_server.await_request(subject)

  assert body == "{\"ok\":true}"
  assert captured.method == "GET"
  assert captured.path == "/wallet"
  assert list.key_find(captured.headers, "accept") == Ok("application/json")
}

pub fn send_unauthenticated_request_error_status_test() {
  let #(base_url, _subject) =
    mock_server.start(status: 404, headers: [], body: "not found")

  assert request.send_unauthenticated_request(base_url <> "/missing")
    == Error(ApiError(status: 404, body: "not found", error: None, as_uri: None))
}

pub fn send_request_parses_error_and_www_authenticate_test() {
  let body =
    json.to_string(
      json.object([
        #(
          "error",
          json.object([
            #("code", json.string("invalid_client")),
            #("description", json.string("Unknown client")),
          ]),
        ),
      ]),
    )
  let #(base_url, _subject) =
    mock_server.start(
      status: 401,
      headers: [#("www-authenticate", "GNAP as_uri=\"https://auth.example/\"")],
      body: body,
    )
  let client = test_client.client()

  assert request.send_request(
      client,
      base_url <> "/resource",
      http.Get,
      None,
      token: None,
    )
    == Error(ApiError(
      status: 401,
      body: body,
      error: Some(ServerError(
        code: InvalidClient,
        description: Some("Unknown client"),
        details: None,
      )),
      as_uri: Some("https://auth.example/"),
    ))
}

pub fn send_unauthenticated_request_unreachable_test() {
  let assert Error(TransportError(_)) =
    request.send_unauthenticated_request(unreachable_url)
}

pub fn send_unauthenticated_and_decode_success_test() {
  let #(base_url, _subject) =
    mock_server.start(status: 200, headers: [], body: "{\"value\":\"abc\"}")

  let decoder = {
    use value <- decode.field("value", decode.string)
    decode.success(value)
  }

  assert request.send_unauthenticated_and_decode(
      base_url,
      decoder: decoder,
      error_context: "ctx",
    )
    == Ok("abc")
}

pub fn send_unauthenticated_and_decode_error_test() {
  let #(base_url, _subject) =
    mock_server.start(status: 200, headers: [], body: "not json")

  let assert Error(DecodeError(message)) =
    request.send_unauthenticated_and_decode(
      base_url,
      decoder: decode.string,
      error_context: "ctx",
    )

  assert string.contains(message, "ctx")
}

pub fn send_request_get_no_body_no_token_test() {
  let #(base_url, subject) =
    mock_server.start(status: 200, headers: [], body: "")
  let client = test_client.client()

  let assert Ok(_) =
    request.send_request(
      client,
      base_url <> "/resource",
      http.Get,
      None,
      token: None,
    )

  let captured = mock_server.await_request(subject)

  assert captured.method == "GET"
  assert captured.path == "/resource"
  assert list.key_find(captured.headers, "content-digest") == Error(Nil)
  assert list.key_find(captured.headers, "authorization") == Error(Nil)

  let assert Ok(signature_input) =
    list.key_find(captured.headers, "signature-input")
  assert string.contains(signature_input, "@method")
  assert string.contains(signature_input, "@target-uri")
  assert !string.contains(signature_input, "content-digest")
  assert !string.contains(signature_input, "authorization")
}

pub fn send_request_post_with_body_test() {
  let #(base_url, subject) =
    mock_server.start(status: 201, headers: [], body: "")
  let client = test_client.client()
  let body = json.object([#("hello", json.string("world"))])

  let assert Ok(_) =
    request.send_request(
      client,
      base_url <> "/resource",
      http.Post,
      Some(body),
      token: None,
    )

  let captured = mock_server.await_request(subject)
  let assert Ok(expected_digest) =
    content_digest.create_digest_header_value(json.to_string(body), "sha-512")

  assert captured.method == "POST"
  assert captured.body == json.to_string(body)
  assert list.key_find(captured.headers, "content-type")
    == Ok("application/json")
  assert list.key_find(captured.headers, "content-digest")
    == Ok(expected_digest)

  let assert Ok(signature_input) =
    list.key_find(captured.headers, "signature-input")
  assert string.contains(signature_input, "content-digest")
}

pub fn send_request_with_token_test() {
  let #(base_url, subject) =
    mock_server.start(status: 200, headers: [], body: "")
  let client = test_client.client()

  let assert Ok(_) =
    request.send_request(
      client,
      base_url <> "/resource",
      http.Get,
      None,
      token: Some("secret-token"),
    )

  let captured = mock_server.await_request(subject)

  assert list.key_find(captured.headers, "authorization")
    == Ok("GNAP secret-token")

  let assert Ok(signature_input) =
    list.key_find(captured.headers, "signature-input")
  assert string.contains(signature_input, "authorization")
}

pub fn send_request_error_status_test() {
  let #(base_url, _subject) =
    mock_server.start(status: 400, headers: [], body: "bad request")
  let client = test_client.client()

  assert request.send_request(
      client,
      base_url <> "/resource",
      http.Get,
      None,
      token: None,
    )
    == Error(ApiError(
      status: 400,
      body: "bad request",
      error: None,
      as_uri: None,
    ))
}

pub fn send_request_unreachable_test() {
  let client = test_client.client()

  let assert Error(TransportError(_)) =
    request.send_request(client, unreachable_url, http.Get, None, token: None)
}

pub fn send_and_decode_success_test() {
  let #(base_url, _subject) =
    mock_server.start(status: 200, headers: [], body: "{\"value\":\"abc\"}")
  let client = test_client.client()

  let decoder = {
    use value <- decode.field("value", decode.string)
    decode.success(value)
  }

  assert request.send_and_decode(
      client,
      base_url <> "/resource",
      http.Get,
      None,
      token: None,
      decoder: decoder,
      error_context: "ctx",
    )
    == Ok("abc")
}

pub fn send_and_decode_error_status_test() {
  let #(base_url, _subject) =
    mock_server.start(status: 404, headers: [], body: "not found")
  let client = test_client.client()

  assert request.send_and_decode(
      client,
      base_url <> "/resource",
      http.Get,
      None,
      token: None,
      decoder: decode.string,
      error_context: "ctx",
    )
    == Error(ApiError(status: 404, body: "not found", error: None, as_uri: None))
}

/// Verifies the signature on a request captured by the mock server with the
/// public key matching the test client's private key, the way an Open
/// Payments server would. `required` lists the components the signature
/// must cover.
fn verify_signature(
  base_url: String,
  captured: CapturedRequest,
  required: List(ComponentIdentifier),
) -> Result(Nil, VerifyError) {
  let assert Ok(pem) = simplifile.read("test/fixtures/private_key")
  let assert Ok(#(_private_key, public_key)) = keys.key_pair_from_pem(pem)
  let assert Ok(signature_input) =
    list.key_find(captured.headers, "signature-input")
  let assert Ok(signature) = list.key_find(captured.headers, "signature")
  let assert Ok(signature_params) =
    verifier.parse(signature_input_header: signature_input, label: "sig1")
  let #(now, _nanoseconds) =
    timestamp.system_time() |> timestamp.to_unix_seconds_and_nanoseconds

  verifier.verify(
    message: message.Request(
      captured.method,
      base_url <> captured.path,
      captured.headers,
    ),
    public_key: public_key,
    signature_params: signature_params,
    signature_header: signature,
    label: "sig1",
    policy: VerifyPolicy(
      required_components: required,
      now: now,
      max_age_seconds: None,
    ),
  )
}

pub fn send_request_signature_verifies_test() {
  let #(base_url, subject) =
    mock_server.start(status: 200, headers: [], body: "")
  let client = test_client.client()

  let assert Ok(_) =
    request.send_request(
      client,
      base_url <> "/resource?wallet-address=abc",
      http.Get,
      None,
      token: None,
    )

  let captured = mock_server.await_request(subject)

  assert verify_signature(base_url, captured, [
      Derived(Method),
      Derived(TargetUri),
    ])
    == Ok(Nil)
}

pub fn send_request_signature_with_body_and_token_verifies_test() {
  let #(base_url, subject) =
    mock_server.start(status: 201, headers: [], body: "")
  let client = test_client.client()
  let body = json.object([#("hello", json.string("world"))])

  let assert Ok(_) =
    request.send_request(
      client,
      base_url <> "/resource",
      http.Post,
      Some(body),
      token: Some("secret-token"),
    )

  let captured = mock_server.await_request(subject)

  assert verify_signature(base_url, captured, [
      Derived(Method),
      Derived(TargetUri),
      Field("content-digest"),
      Field("authorization"),
    ])
    == Ok(Nil)
}

pub fn send_request_signature_rejects_tampered_request_test() {
  let #(base_url, subject) =
    mock_server.start(status: 200, headers: [], body: "")
  let client = test_client.client()

  let assert Ok(_) =
    request.send_request(
      client,
      base_url <> "/resource",
      http.Get,
      None,
      token: Some("secret-token"),
    )

  let captured = mock_server.await_request(subject)
  let tampered =
    mock_server.CapturedRequest(
      ..captured,
      headers: list.key_set(
        captured.headers,
        "authorization",
        "GNAP other-token",
      ),
    )

  assert verify_signature(base_url, tampered, [
      Derived(Method),
      Derived(TargetUri),
      Field("authorization"),
    ])
    == Error(verifier.InvalidSignature)
}
