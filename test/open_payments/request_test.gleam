import gleam/dynamic/decode
import gleam/http
import gleam/http/response.{Response}
import gleam/httpc
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import http_digest_fields/content_digest
import open_payments/error.{ApiError, DecodeError, TransportError}
import open_payments/request
import support/mock_server
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

pub fn handle_response_error_status_test() {
  let resp = Ok(Response(status: 404, headers: [], body: "not found"))

  assert request.handle_response(resp)
    == Error(ApiError(status: 404, body: "not found"))
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
    == Error(ApiError(status: 404, body: "not found"))
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
    == Error(ApiError(status: 400, body: "bad request"))
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
    == Error(ApiError(status: 404, body: "not found"))
}
