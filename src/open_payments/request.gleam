import gleam/http/request
import gleam/httpc

pub fn send_unauthenticated_request(url: String) {
  let assert Ok(base_req) = request.to(url)
  let req = request.prepend_header(base_req, "accept", "application/json")
  let resp = httpc.send(req)

  case resp {
    Ok(resp) if resp.status == 200 -> Ok(resp.body)
    _ -> Error("REQUEST_FAILED")
  }
}
