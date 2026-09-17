import gleam/bit_array
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/string

/// A single request captured by a mock server started with `start`.
pub type CapturedRequest {
  CapturedRequest(
    method: String,
    path: String,
    headers: List(#(String, String)),
    body: String,
  )
}

type Socket

@external(erlang, "mock_server_ffi", "listen")
fn ffi_listen() -> #(Socket, Int)

@external(erlang, "mock_server_ffi", "serve_one")
fn ffi_serve_one(socket: Socket, response: String) -> String

/// Starts a local HTTP server that accepts exactly one connection, replies
/// with the given canned response, and then shuts down. Returns the base
/// URL to send a request to, and a `Subject` that will receive the request
/// the server captured once it has been served (see `await_request`).
pub fn start(
  status status: Int,
  headers headers: List(#(String, String)),
  body body: String,
) -> #(String, Subject(CapturedRequest)) {
  let #(socket, port) = ffi_listen()
  let base_url = "http://127.0.0.1:" <> int.to_string(port)
  let response = build_response(status, headers, body)
  let subject = process.new_subject()

  process.spawn(fn() {
    let raw_request = ffi_serve_one(socket, response)
    process.send(subject, parse_request(raw_request))
  })

  #(base_url, subject)
}

/// Waits for the request captured by a server started with `start`. Panics
/// if no request arrives within 2 seconds.
pub fn await_request(subject: Subject(CapturedRequest)) -> CapturedRequest {
  let assert Ok(captured) = process.receive(subject, within: 2000)
  captured
}

fn status_text(status: Int) -> String {
  case status {
    200 -> "OK"
    201 -> "Created"
    204 -> "No Content"
    400 -> "Bad Request"
    404 -> "Not Found"
    _ -> "Status"
  }
}

fn build_response(
  status: Int,
  headers: List(#(String, String)),
  body: String,
) -> String {
  let content_length =
    body |> bit_array.from_string |> bit_array.byte_size |> int.to_string
  let headers = [#("content-length", content_length), ..headers]

  let header_lines =
    headers
    |> list.map(fn(header) { header.0 <> ": " <> header.1 })
    |> string.join("\r\n")

  "HTTP/1.1 "
  <> int.to_string(status)
  <> " "
  <> status_text(status)
  <> "\r\n"
  <> header_lines
  <> "\r\n\r\n"
  <> body
}

fn parse_request(raw: String) -> CapturedRequest {
  let #(head, body) = case string.split_once(raw, "\r\n\r\n") {
    Ok(parts) -> parts
    Error(_) -> #(raw, "")
  }

  let assert [request_line, ..header_lines] = string.split(head, "\r\n")
  let #(method, path) = parse_request_line(request_line)

  let headers =
    header_lines
    |> list.filter_map(fn(line) {
      case string.split_once(line, ": ") {
        Ok(#(name, value)) -> Ok(#(string.lowercase(name), value))
        Error(_) -> Error(Nil)
      }
    })

  CapturedRequest(method: method, path: path, headers: headers, body: body)
}

fn parse_request_line(line: String) -> #(String, String) {
  case string.split(line, " ") {
    [method, path, ..] -> #(method, path)
    _ -> #("", "")
  }
}
