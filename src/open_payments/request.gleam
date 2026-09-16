import gleam/http
import gleam/http/request
import gleam/http/response.{type Response}
import gleam/httpc
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/timestamp
import http_digest_fields/content_digest
import http_message_signatures/component.{Derived, Field, Method, TargetUri}
import http_message_signatures/keys
import http_message_signatures/message
import http_message_signatures/params.{SignatureParams}
import http_message_signatures/signer
import open_payments/client.{type Client}

const signature_max_age_seconds = 300

/// Sends an unsigned GET request to `url` and returns the response body.
/// Used for endpoints that don't require an access token or request
/// signature, such as fetching wallet address details.
pub fn send_unauthenticated_request(url: String) {
  let assert Ok(base_req) = request.to(url)
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
) {
  let digest_header = case body {
    Some(b) -> {
      let assert Ok(header) =
        content_digest.create_digest_header_value(json.to_string(b), "sha-512")
      Some(header)
    }
    None -> None
  }

  let assert Ok(base_req) = request.to(url)
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

  let assert Ok(#(private_key, _public_key)) =
    keys.key_pair_from_pem(client.private_key)
  let assert Ok(signed) =
    signer.sign(message_to_sign, private_key, "sig1", signature_params)

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
