import gleam/http/response.{Response}
import gleam/httpc
import open_payments/error.{ApiError, TransportError}
import open_payments/request

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
