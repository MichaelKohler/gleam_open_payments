import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import open_payments/error.{
  ApiError, InvalidClient, InvalidContinuation, InvalidRequest, InvalidRotation,
  OtherErrorCode, RequestDenied, ServerError, TooFast,
}

pub fn decode_error_code_test() {
  let decode_code = fn(code) {
    json.parse(json.to_string(json.string(code)), error.decode_error_code())
  }

  assert decode_code("invalid_client") == Ok(InvalidClient)
  assert decode_code("invalid_request") == Ok(InvalidRequest)
  assert decode_code("request_denied") == Ok(RequestDenied)
  assert decode_code("too_fast") == Ok(TooFast)
  assert decode_code("invalid_continuation") == Ok(InvalidContinuation)
  assert decode_code("invalid_rotation") == Ok(InvalidRotation)
  assert decode_code("invalid_receiver")
    == Ok(OtherErrorCode("invalid_receiver"))
}

pub fn decode_server_error_object_test() {
  let body =
    json.to_string(
      json.object([
        #(
          "error",
          json.object([
            #("code", json.string("too_fast")),
            #("description", json.string("Polled too quickly")),
          ]),
        ),
      ]),
    )

  assert json.parse(body, error.decode_server_error())
    == Ok(ServerError(
      code: TooFast,
      description: Some("Polled too quickly"),
      details: None,
    ))
}

pub fn decode_server_error_with_details_test() {
  let body =
    json.to_string(
      json.object([
        #(
          "error",
          json.object([
            #("code", json.string("invalid_receiver")),
            #("description", json.string("Receiver is not valid")),
            #("details", json.object([#("receiver", json.string("missing"))])),
          ]),
        ),
      ]),
    )

  let assert Ok(ServerError(
    code: OtherErrorCode("invalid_receiver"),
    description: Some("Receiver is not valid"),
    details: Some(details),
  )) = json.parse(body, error.decode_server_error())

  assert decode.run(details, decode.at(["receiver"], decode.string))
    == Ok("missing")
}

pub fn decode_server_error_string_test() {
  let body = json.to_string(json.object([#("error", json.string("too_fast"))]))

  assert json.parse(body, error.decode_server_error())
    == Ok(ServerError(code: TooFast, description: None, details: None))
}

pub fn parse_as_uri_quoted_test() {
  assert error.parse_as_uri("GNAP as_uri=\"https://auth.example/\"")
    == Some("https://auth.example/")
}

pub fn parse_as_uri_unquoted_test() {
  assert error.parse_as_uri("GNAP as_uri=https://auth.example/")
    == Some("https://auth.example/")
}

pub fn parse_as_uri_with_other_params_test() {
  assert error.parse_as_uri(
      "gnap realm=\"rs\", as_uri=\"https://auth.example/\"",
    )
    == Some("https://auth.example/")
}

pub fn parse_as_uri_other_scheme_test() {
  assert error.parse_as_uri("Bearer as_uri=\"https://auth.example/\"") == None
}

pub fn parse_as_uri_missing_test() {
  assert error.parse_as_uri("GNAP realm=\"rs\"") == None
}

pub fn from_response_parses_error_and_as_uri_test() {
  let body =
    json.to_string(
      json.object([
        #("error", json.object([#("code", json.string("invalid_client"))])),
      ]),
    )

  assert error.from_response(
      status: 401,
      body: body,
      www_authenticate: Ok("GNAP as_uri=\"https://auth.example/\""),
    )
    == ApiError(
      status: 401,
      body: body,
      error: Some(ServerError(
        code: InvalidClient,
        description: None,
        details: None,
      )),
      as_uri: Some("https://auth.example/"),
    )
}

pub fn from_response_unstructured_body_test() {
  assert error.from_response(
      status: 404,
      body: "not found",
      www_authenticate: Error(Nil),
    )
    == ApiError(status: 404, body: "not found", error: None, as_uri: None)
}
