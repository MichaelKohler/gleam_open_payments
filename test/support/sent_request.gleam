import gleam/http
import gleam/http/request.{type Request}
import gleam/option.{None, Some}
import gleam/string

/// The parts of a built request that tests assert on, in the same shape as
/// `mock_server.CapturedRequest` so assertions read the same on every
/// target.
pub type SentRequest {
  SentRequest(
    method: String,
    path: String,
    headers: List(#(String, String)),
    body: String,
  )
}

/// Captures what `req` would put on the wire, without sending it.
pub fn capture(req: Request(String)) -> SentRequest {
  let path = case req.path {
    "" -> "/"
    path -> path
  }
  let path = case req.query {
    Some(query) -> path <> "?" <> query
    None -> path
  }

  SentRequest(
    method: string.uppercase(http.method_to_string(req.method)),
    path: path,
    headers: req.headers,
    body: req.body,
  )
}
