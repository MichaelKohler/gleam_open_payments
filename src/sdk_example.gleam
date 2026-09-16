import gleam/erlang/charlist
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import open_payments/client
import open_payments/grants.{
  type GrantResponse, AccessIncoming, AccessOutgoing, AccessQuote, DebitAmount,
  Finish, Grant, GrantOptions, IncomingComplete, IncomingCreate, IncomingList,
  IncomingRead, IncomingReadAll, Interact, Limits, OutgoingCreate, PendingGrant,
  QuoteCreate, QuoteRead,
}
import open_payments/incoming_payment.{
  type IncomingPayment, type IncomingPaymentList, CreateOptions, ListOptions,
}
import open_payments/types.{type Amount, type Key, Amount}
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

  let access =
    AccessIncoming(
      [
        IncomingCreate, IncomingRead, IncomingReadAll, IncomingList,
        IncomingComplete,
      ],
      Some(address),
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
        True -> panic as "Grant should not require interaction!"
        False -> {
          print_grant(grant)
          case grant {
            Grant(access_token: token, continue: continue) -> {
              run_incoming_payment_flow(
                client,
                address_info,
                address,
                token.value,
              )

              section("Cancel incoming payment grant")

              case grants.cancel(client, continue) {
                Ok(_) -> io.println("  Grant canceled.")
                Error(err) -> print_error("Failed to cancel grant", err)
              }
            }
            PendingGrant(..) -> Nil
          }
        }
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
        False -> print_grant(grant)
      }
    Error(err) -> print_error("Failed to request grant", err)
  }

  section("Outgoing payment grant")

  let amount = Amount("20", "USD", 2)
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

fn run_incoming_payment_flow(
  client: client.Client,
  address_info: WalletInfo,
  address: String,
  access_token: String,
) -> Nil {
  section("Create incoming payment")

  let create_options =
    CreateOptions(
      resource_server: address_info.resource_server,
      wallet_address: address,
      incoming_amount: Some(Amount(
        "100",
        address_info.asset_code,
        address_info.asset_scale,
      )),
      expires_at: None,
      metadata: None,
    )

  case incoming_payment.create(client, access_token, create_options) {
    Ok(payment) -> {
      print_incoming_payment(payment)

      section("List incoming payments")

      let list_options =
        ListOptions(
          resource_server: address_info.resource_server,
          wallet_address: address,
          cursor: None,
          first: None,
          last: None,
        )

      case incoming_payment.list(client, access_token, list_options) {
        Ok(payment_list) -> print_incoming_payment_list(payment_list)
        Error(err) -> print_error("Failed to list incoming payments", err)
      }

      section("Get incoming payment")

      case incoming_payment.get(client, access_token, payment.id) {
        Ok(fetched) -> print_incoming_payment(fetched)
        Error(err) -> print_error("Failed to get incoming payment", err)
      }

      section("Complete incoming payment")

      case incoming_payment.complete(client, access_token, payment.id) {
        Ok(completed) -> print_incoming_payment(completed)
        Error(err) -> print_error("Failed to complete incoming payment", err)
      }
    }
    Error(err) -> print_error("Failed to create incoming payment", err)
  }
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

fn print_amount(amount: Amount) -> String {
  amount.value
  <> " "
  <> amount.asset_code
  <> " (scale "
  <> int.to_string(amount.asset_scale)
  <> ")"
}

fn print_incoming_payment(payment: IncomingPayment) -> Nil {
  field("ID", payment.id)
  field("Wallet address", payment.wallet_address)
  field("Completed", case payment.completed {
    True -> "yes"
    False -> "no"
  })
  case payment.incoming_amount {
    Some(amount) -> field("Incoming amount", print_amount(amount))
    None -> Nil
  }
  field("Received amount", print_amount(payment.received_amount))
  field("Created at", payment.created_at)
  case payment.methods {
    [] -> Nil
    methods ->
      list.each(methods, fn(method) {
        io.println("    - ILP address: " <> method.ilp_address)
      })
  }
}

fn print_incoming_payment_list(payment_list: IncomingPaymentList) -> Nil {
  field("Has next page", case payment_list.pagination.has_next_page {
    True -> "yes"
    False -> "no"
  })
  case payment_list.result {
    [] -> io.println("  (no incoming payments found)")
    payments ->
      list.each(payments, fn(payment) {
        io.println(
          "  - "
          <> payment.id
          <> " (received "
          <> print_amount(payment.received_amount)
          <> ")",
        )
      })
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
