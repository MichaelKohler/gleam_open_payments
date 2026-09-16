import gleam/erlang/charlist
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import open_payments/client
import open_payments/grants.{
  type GrantResponse, AccessIncoming, AccessOutgoing, AccessQuote, Amount,
  DebitAmount, Finish, Grant, GrantOptions, IncomingRead, IncomingReadAll,
  Interact, Limits, OutgoingCreate, PendingGrant, QuoteCreate, QuoteRead,
}
import open_payments/types.{type Key}
import open_payments/wallet_address.{type WalletInfo}

pub fn main() -> Nil {
  let client =
    client.create(
      "https://ilp.interledger-test.dev/michaelusd",
      "be52ffa9-b61b-4a8c-8dbe-43b75cda31c9",
      "fixtures/private_key",
    )

  section("Wallet address")

  let address = "https://ilp.interledger-test.dev/michaeleur"
  let assert Ok(address_info) = wallet_address.get(address)
  print_wallet_info(address_info)

  section("Wallet keys")

  case wallet_address.get_keys(address) {
    Ok(keys) -> print_keys(keys)
    Error(err) -> print_error("Failed to get keys", err)
  }

  section("Incoming payment grant")

  let access = AccessIncoming([IncomingRead, IncomingReadAll], None)
  let interact =
    Interact(
      ["redirect"],
      Some(Finish("redirect", "https://example.com/finish", "nonce")),
    )
  let grant_options =
    GrantOptions(address_info.auth_server, access, interact, address)

  case grants.request(client, grant_options) {
    Ok(grant) ->
      case grants.is_interactive_grant(grant) {
        True -> panic as "Grant should not require interaction!"
        False -> handle_approved_grant(grant)
      }
    Error(err) -> print_error("Failed to request grant", err)
  }

  section("Quote grant")

  let access = AccessQuote([QuoteRead, QuoteCreate])
  let interact =
    Interact(
      ["redirect"],
      Some(Finish("redirect", "https://example.com/finish", "nonce")),
    )
  let grant_options =
    GrantOptions(address_info.auth_server, access, interact, address)

  case grants.request(client, grant_options) {
    Ok(grant) ->
      case grants.is_interactive_grant(grant) {
        True -> panic as "Grant should not require interaction!"
        False -> handle_approved_grant(grant)
      }
    Error(err) -> print_error("Failed to request grant", err)
  }

  section("Outgoing payment grant")

  let amount = Amount(20, "USD", 2)
  let debit_amount = DebitAmount(amount)
  let incoming_payment_url =
    "https://ilp.interledger-test.dev/incoming-payments/placeholder"
  let limits =
    Limits(
      receiver: Some(incoming_payment_url),
      amount: debit_amount,
      interval: None,
    )
  let access =
    AccessOutgoing(
      actions: [OutgoingCreate],
      identifier: address,
      limits: Some(limits),
    )
  let interact =
    Interact(
      ["redirect"],
      Some(Finish("redirect", "https://example.com/finish", "nonce")),
    )
  let grant_options =
    GrantOptions(address_info.auth_server, access, interact, address)

  case grants.request(client, grant_options) {
    Ok(grant) ->
      case grants.is_interactive_grant(grant) {
        True -> handle_pending_grant(client, grant)
        False -> panic as "Grant should require interaction!"
      }
    Error(err) -> print_error("Failed to request grant", err)
  }
}

fn handle_approved_grant(grant: GrantResponse) -> Nil {
  print_grant(grant)
}

fn handle_pending_grant(client: client.Client, grant: GrantResponse) -> Nil {
  case grant {
    PendingGrant(interact: interact, continue: continue) -> {
      io.println("  Status:   pending interaction")
      io.println("  Redirect: " <> interact.redirect)
      io.println("")
      let interact_ref = prompt("Paste the interact_ref once approved: ")

      case grants.continue(client, continue, interact_ref) {
        Ok(continuation) -> print_continuation(continuation)
        Error(err) -> print_error("Failed to continue grant", err)
      }
    }
    Grant(..) -> panic as "Expected a pending grant"
  }
}

fn section(title: String) -> Nil {
  io.println("")
  io.println(title)
  io.println(string.repeat("-", string.length(title)))
}

fn field(label: String, value: String) -> Nil {
  io.println("  " <> string.pad_end(label <> ":", 16, " ") <> value)
}

fn print_error(context: String, reason: String) -> Nil {
  io.println("  Error: " <> context <> " - " <> reason)
}

fn print_wallet_info(info: WalletInfo) -> Nil {
  field("ID", info.id)
  field("Name", info.public_name)
  field(
    "Asset",
    info.asset_code <> " (scale " <> int.to_string(info.asset_scale) <> ")",
  )
  field("Auth server", info.auth_server)
  field("Resource server", info.resource_server)
}

fn print_keys(keys: List(Key)) -> Nil {
  case keys {
    [] -> io.println("  (no keys found)")
    _ ->
      list.each(keys, fn(key) {
        io.println(
          "  - kid: "
          <> key.kid
          <> ", kty: "
          <> key.kty
          <> ", crv: "
          <> key.crv
          <> ", alg: "
          <> key.alg,
        )
      })
  }
}

fn print_grant(grant: GrantResponse) -> Nil {
  case grant {
    Grant(access_token: token, ..) -> {
      field("Status", "approved")
      field("Access token", token.value)
      field("Manage URL", token.manage)
      case token.expires_in {
        Some(seconds) -> field("Expires in", int.to_string(seconds) <> "s")
        None -> Nil
      }
    }
    PendingGrant(interact: interact, ..) -> {
      field("Status", "pending interaction")
      field("Redirect", interact.redirect)
    }
  }
}

fn print_continuation(continuation: grants.ContinuationResponse) -> Nil {
  case continuation.access_token {
    Some(token) -> {
      field("Status", "continuation succeeded")
      field("Access token", token.value)
      field("Manage URL", token.manage)
    }
    None -> field("Status", "continuation succeeded, no access token issued")
  }
}

@external(erlang, "io", "get_line")
fn erlang_get_line(prompt: charlist.Charlist) -> charlist.Charlist

fn prompt(message: String) -> String {
  message
  |> charlist.from_string
  |> erlang_get_line
  |> charlist.to_string
  |> string.trim
}
