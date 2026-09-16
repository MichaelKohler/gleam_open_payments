import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/timestamp
import http_digest_fields/content_digest
import http_message_signatures/component.{Derived, Field, Method, TargetUri}
import http_message_signatures/message
import http_message_signatures/params.{SignatureParams}
import http_message_signatures/signer
import open_payments/client.{type Client}

const signature_max_age_seconds = 300

/// Sends an unsigned GET request to `url` and returns the response body.
/// Used for endpoints that don't require an access token or request
/// signature, such as fetching wallet address details.
pub fn send_unauthenticated_request(url: String) -> Result(String, String) {
  use base_req <- result.try(
    request.to(url) |> result.replace_error("Invalid URL: " <> url),
  )
  let req = request.prepend_header(base_req, "accept", "application/json")
  let resp = httpc.send(req)

  handle_response(resp)
}

/// Sends an HTTP message signed with `client`'s private key to `url`, and
/// returns the response body. When `body` is given, a `content-digest`
/// header is attached and covered by the signature; when `token` is given,
/// it is sent as a `GNAP` authorization header and likewise signed.
pub fn send_request(
  client: Client,
  url: String,
  method: http.Method,
  body: Option(Json),
  token token: Option(String),
) -> Result(String, String) {
  use digest_header <- result.try(case body {
    Some(b) ->
      content_digest.create_digest_header_value(json.to_string(b), "sha-512")
      |> result.map(Some)
      |> result.map_error(fn(err) {
        "Failed to create content digest: " <> string.inspect(err)
      })
    None -> Ok(None)
  })

  use base_req <- result.try(
    request.to(url) |> result.replace_error("Invalid URL: " <> url),
  )

  let unsigned_req =
    base_req
    |> request.set_method(method)
    |> request.prepend_header("accept", "application/json")

  let unsigned_req = case body {
    Some(_) ->
      request.prepend_header(unsigned_req, "content-type", "application/json")
    None -> unsigned_req
  }

  let unsigned_req = case digest_header {
    Some(h) -> request.prepend_header(unsigned_req, "content-digest", h)
    None -> unsigned_req
  }

  let unsigned_req = case token {
    Some(t) ->
      request.prepend_header(unsigned_req, "authorization", "GNAP " <> t)
    None -> unsigned_req
  }

  let #(created, _nanoseconds) =
    timestamp.system_time() |> timestamp.to_unix_seconds_and_nanoseconds

  let signed_components =
    [Derived(Method), Derived(TargetUri)]
    |> list.append(case digest_header {
      Some(_) -> [Field("content-digest")]
      None -> []
    })
    |> list.append(case token {
      Some(_) -> [Field("authorization")]
      None -> []
    })

  let signature_params =
    SignatureParams(
      components: signed_components,
      key_id: client.key_id,
      algorithm: "ed25519",
      created: Some(created),
      expires: Some(created + signature_max_age_seconds),
    )

  let message_to_sign =
    message.Request(http.method_to_string(method), url, unsigned_req.headers)

  use signed <- result.try(
    signer.sign(message_to_sign, client.private_key, "sig1", signature_params)
    |> result.map_error(fn(err) {
      "Failed to sign request: " <> string.inspect(err)
    }),
  )

  let req =
    unsigned_req
    |> request.prepend_header("signature-input", signed.signature_input)
    |> request.prepend_header("signature", signed.signature)

  let req = case body {
    Some(b) -> request.set_body(req, json.to_string(b))
    None -> req
  }

  let resp = httpc.send(req)

  handle_response(resp)
}

/// Sends a signed request via `send_request` and decodes the JSON response
/// body with `decoder`. A decode failure is wrapped as
/// `error_context <> ": " <> <the underlying decode error>`, so callers get
/// a message that both names the response and shows what went wrong parsing
/// it.
pub fn send_and_decode(
  client: Client,
  url: String,
  method: http.Method,
  body: Option(Json),
  token token: Option(String),
  decoder decoder: decode.Decoder(a),
  error_context error_context: String,
) -> Result(a, String) {
  use response_body <- result.try(send_request(
    client,
    url,
    method,
    body,
    token: token,
  ))

  json.parse(response_body, decoder)
  |> result.map_error(fn(err) { error_context <> ": " <> string.inspect(err) })
}

@internal
pub fn handle_response(
  resp: Result(Response(String), httpc.HttpError),
) -> Result(String, String) {
  case resp {
    Ok(resp) if resp.status == 200 || resp.status == 201 || resp.status == 204 ->
      Ok(resp.body)
    Ok(resp) ->
      Error(
        "Request failed with status "
        <> int.to_string(resp.status)
        <> ": "
        <> resp.body,
      )
    Error(err) -> Error("Request failed: " <> string.inspect(err))
  }
}
