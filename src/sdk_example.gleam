import gleam/erlang/charlist
import gleam/io
import gleam/option.{None, Some}
import gleam/string
import open_payments/client
import open_payments/grants.{
  type GrantResponse, AccessIncoming, AccessOutgoing, AccessQuote, Amount,
  DebitAmount, Finish, Grant, GrantOptions, IncomingRead, IncomingReadAll,
  Interact, Limits, OutgoingCreate, PendingGrant, QuoteCreate, QuoteRead,
}
import open_payments/wallet_address

pub fn main() -> Nil {
  let client =
    client.create(
      "https://ilp.interledger-test.dev/michaelusd",
      "be52ffa9-b61b-4a8c-8dbe-43b75cda31c9",
      "fixtures/private_key",
    )

  // WALLET ADDRESS AND KEYS

  let address = "https://ilp.interledger-test.dev/michaeleur"
  let assert Ok(address_info) = wallet_address.get(address)
  io.println("Wallet address info: " <> string.inspect(address_info))

  let keys = wallet_address.get_keys(address)

  case keys {
    Ok(keys) -> io.println("Keys: " <> string.inspect(keys))
    Error(err) -> io.println("Failed to get keys: " <> err)
  }

  // INCOMING PAYMENT GRANT

  let access = AccessIncoming([IncomingRead, IncomingReadAll], None)
  let interact =
    Interact(
      ["redirect"],
      Some(Finish("redirect", "https://example.com/finish", "nonce")),
    )
  let grant_options =
    GrantOptions(address_info.auth_server, access, interact, address)

  let response = grants.request(client, grant_options)
  case response {
    Ok(grant) ->
      case grants.is_interactive_grant(grant) {
        True -> panic as "Grant should not require interaction!"
        False -> handle_approved_grant(grant)
      }
    Error(err) -> io.println("Failed to request grant: " <> err)
  }

  // QUOTE GRANT

  let access = AccessQuote([QuoteRead, QuoteCreate])
  let interact =
    Interact(
      ["redirect"],
      Some(Finish("redirect", "https://example.com/finish", "nonce")),
    )
  let grant_options =
    GrantOptions(address_info.auth_server, access, interact, address)

  let response = grants.request(client, grant_options)
  case response {
    Ok(grant) ->
      case grants.is_interactive_grant(grant) {
        True -> panic as "Grant should not require interaction!"
        False -> handle_approved_grant(grant)
      }
    Error(err) -> io.println("Failed to request grant: " <> err)
  }

  // OUTGOING PAYMENT GRANT

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

  let response = grants.request(client, grant_options)
  case response {
    Ok(grant) ->
      case grants.is_interactive_grant(grant) {
        True -> handle_pending_grant(client, grant)
        False -> panic as "Grant should require interaction!"
      }
    Error(err) -> io.println("Failed to request grant: " <> err)
  }
}

fn handle_approved_grant(grant: GrantResponse) {
  io.println("Grant approved: " <> string.inspect(grant))
}

fn handle_pending_grant(client: client.Client, grant: GrantResponse) -> Nil {
  case grant {
    PendingGrant(interact: interact, continue: continue) -> {
      io.println("Please approve this grant by visiting: " <> interact.redirect)
      let interact_ref = prompt("Paste the interact_ref once approved: ")

      case grants.continue(client, continue, interact_ref) {
        Ok(continuation_response) ->
          io.println(
            "Continuation succeeded: " <> string.inspect(continuation_response),
          )
        Error(err) -> io.println("Failed to continue grant: " <> err)
      }
    }
    Grant(..) -> panic as "Expected a pending grant"
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
