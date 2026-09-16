import gleam/erlang/charlist
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import open_payments/access_token
import open_payments/client
import open_payments/error.{
  type OpenPaymentsError, ApiError, DecodeError, KeyError, TransportError,
}
import open_payments/grants.{
  type GrantResponse, Finish, Grant, GrantOptions, Interact, PendingGrant,
}
import open_payments/incoming_payment.{
  type IncomingPayment, type IncomingPaymentList, CreateOptions, ListOptions,
}
import open_payments/outgoing_payment.{
  type GrantSpentAmounts, type OutgoingPayment, type OutgoingPaymentList,
  FromIncomingPayment, FromQuote,
}
import open_payments/quotes.{type Quote}
import open_payments/types.{
  type AccessTokenResponse, type Amount, type Key, AccessIncoming,
  AccessOutgoing, AccessQuote, Amount, DebitAmount, IncomingComplete,
  IncomingCreate, IncomingList, IncomingRead, IncomingReadAll, Limits,
  OutgoingCreate, OutgoingList, OutgoingRead, OutgoingReadAll, QuoteCreate,
  QuoteRead,
}
import open_payments/wallet_address.{type WalletInfo}

pub fn main() -> Nil {
  let assert Ok(client) =
    client.create(
      wallet_address_url: "https://ilp.interledger-test.dev/michaelusd",
      key_id: "be52ffa9-b61b-4a8c-8dbe-43b75cda31c9",
      private_key_path: "fixtures/private_key",
    )
  let sender_address = "https://ilp.interledger-test.dev/michaelusd"
  let receiver_address = "https://ilp.interledger-test.dev/michaeleur"

  let sender_address_info = fetch_wallet_address_section(sender_address)
  fetch_wallet_keys_section(sender_address)
  let receiver_address_info = fetch_wallet_address_section(receiver_address)
  fetch_wallet_keys_section(receiver_address)
  request_incoming_payment_grant_section(
    client,
    sender_address_info,
    sender_address,
    receiver_address_info,
    receiver_address,
  )
}

fn fetch_wallet_address_section(address: String) -> WalletInfo {
  section("Wallet address")

  let assert Ok(address_info) = wallet_address.get(address)
  print_wallet_info(address_info)
  address_info
}

fn fetch_wallet_keys_section(address: String) -> Nil {
  section("Wallet keys")

  case wallet_address.get_keys(address) {
    Ok(keys) -> print_keys(keys)
    Error(err) -> print_error("Failed to get keys", err)
  }
}

fn request_incoming_payment_grant_section(
  client: client.Client,
  sender_address_info: WalletInfo,
  sender_address: String,
  receiver_address_info: WalletInfo,
  receiver_address: String,
) -> Nil {
  section("Incoming payment grant")

  let access =
    AccessIncoming(
      actions: [
        IncomingCreate, IncomingRead, IncomingReadAll, IncomingList,
        IncomingComplete,
      ],
      identifier: Some(receiver_address),
    )
  let grant_options =
    GrantOptions(
      auth_server_url: receiver_address_info.auth_server,
      access: [access],
      interact: None,
      address: receiver_address,
    )

  case grants.request(client, grant_options) {
    Ok(grant) ->
      case grants.is_interactive_grant(grant) {
        True -> panic as "Grant should not require interaction!"
        False -> {
          print_grant(grant)
          case grant {
            Grant(access_token: token, continue: continue) ->
              run_incoming_payment_flow(
                client,
                sender_address_info,
                sender_address,
                receiver_address_info,
                receiver_address,
                token.value,
                continue,
              )
            PendingGrant(..) -> Nil
          }
        }
      }
    Error(err) -> print_error("Failed to request grant", err)
  }
}

fn run_incoming_payment_flow(
  client: client.Client,
  sender_address_info: WalletInfo,
  sender_address: String,
  receiver_address_info: WalletInfo,
  receiver_address: String,
  access_token: String,
  continue: grants.ContinueResponse,
) -> Nil {
  case
    create_incoming_payment_section(
      client,
      access_token,
      receiver_address_info,
      receiver_address,
    )
  {
    Ok(payment) -> {
      list_incoming_payments_section(
        client,
        access_token,
        receiver_address_info,
        receiver_address,
      )
      get_incoming_payment_section(client, access_token, payment.id)
      request_quote_grant_section(
        client,
        sender_address_info,
        sender_address,
        payment.id,
      )
      complete_incoming_payment_section(client, access_token, payment.id)
    }
    Error(_) -> Nil
  }

  cancel_incoming_payment_grant_section(client, continue)
}

fn create_incoming_payment_section(
  client: client.Client,
  access_token: String,
  address_info: WalletInfo,
  address: String,
) -> Result(IncomingPayment, OpenPaymentsError) {
  section("Create incoming payment")

  let create_options =
    CreateOptions(
      resource_server: address_info.resource_server,
      wallet_address: address,
      incoming_amount: Some(Amount(
        value: "10000",
        asset_code: address_info.asset_code,
        asset_scale: address_info.asset_scale,
      )),
      expires_at: None,
      metadata: None,
    )

  case incoming_payment.create(client, access_token, create_options) {
    Ok(payment) -> {
      print_incoming_payment(payment)
      Ok(payment)
    }
    Error(err) -> {
      print_error("Failed to create incoming payment", err)
      Error(err)
    }
  }
}

fn list_incoming_payments_section(
  client: client.Client,
  access_token: String,
  address_info: WalletInfo,
  address: String,
) -> Nil {
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
}

fn get_incoming_payment_section(
  client: client.Client,
  access_token: String,
  payment_id: String,
) -> Nil {
  section("Get incoming payment")

  case incoming_payment.get(client, access_token, payment_id) {
    Ok(fetched) -> print_incoming_payment(fetched)
    Error(err) -> print_error("Failed to get incoming payment", err)
  }
}

fn complete_incoming_payment_section(
  client: client.Client,
  access_token: String,
  payment_id: String,
) -> Nil {
  section("Complete incoming payment")

  case incoming_payment.complete(client, access_token, payment_id) {
    Ok(completed) -> print_incoming_payment(completed)
    Error(err) -> print_error("Failed to complete incoming payment", err)
  }
}

fn cancel_incoming_payment_grant_section(
  client: client.Client,
  continue: grants.ContinueResponse,
) -> Nil {
  section("Cancel incoming payment grant")

  case grants.cancel(client, continue) {
    Ok(_) -> io.println("  Grant canceled.")
    Error(err) -> print_error("Failed to cancel grant", err)
  }
}

fn request_quote_grant_section(
  client: client.Client,
  sender_address_info: WalletInfo,
  sender_address: String,
  incoming_payment_id: String,
) -> Nil {
  section("Quote grant")

  let access = AccessQuote([QuoteRead, QuoteCreate])
  let grant_options =
    GrantOptions(
      auth_server_url: sender_address_info.auth_server,
      access: [access],
      interact: None,
      address: sender_address,
    )

  case grants.request(client, grant_options) {
    Ok(grant) ->
      case grants.is_interactive_grant(grant) {
        True -> panic as "Grant should not require interaction!"
        False -> {
          print_grant(grant)
          case grant {
            Grant(access_token: token, ..) ->
              run_quote_operations(
                client,
                sender_address_info,
                sender_address,
                token.value,
                incoming_payment_id,
              )
            PendingGrant(..) -> Nil
          }
        }
      }
    Error(err) -> print_error("Failed to request grant", err)
  }
}

fn run_quote_operations(
  client: client.Client,
  sender_address_info: WalletInfo,
  sender_address: String,
  access_token: String,
  incoming_payment_id: String,
) -> Nil {
  case
    create_quote_section(
      client,
      access_token,
      sender_address_info,
      sender_address,
      incoming_payment_id,
    )
  {
    Ok(quote) -> {
      get_quote_section(client, access_token, quote.id)
      request_outgoing_payment_grant_section(
        client,
        sender_address_info,
        sender_address,
        quote,
        incoming_payment_id,
      )
    }
    Error(_) -> Nil
  }
}

fn create_quote_section(
  client: client.Client,
  access_token: String,
  sender_address_info: WalletInfo,
  sender_address: String,
  incoming_payment_id: String,
) -> Result(Quote, OpenPaymentsError) {
  section("Create quote")

  let create_options =
    quotes.CreateOptions(
      resource_server: sender_address_info.resource_server,
      wallet_address: sender_address,
      receiver: incoming_payment_id,
      amount: DebitAmount(Amount(
        value: "5000",
        asset_code: sender_address_info.asset_code,
        asset_scale: sender_address_info.asset_scale,
      )),
    )

  case quotes.create(client, access_token, create_options) {
    Ok(quote) -> {
      print_quote(quote)
      Ok(quote)
    }
    Error(err) -> {
      print_error("Failed to create quote", err)
      Error(err)
    }
  }
}

fn get_quote_section(
  client: client.Client,
  access_token: String,
  quote_id: String,
) -> Nil {
  section("Get quote")

  case quotes.get(client, access_token, quote_id) {
    Ok(fetched) -> print_quote(fetched)
    Error(err) -> print_error("Failed to get quote", err)
  }
}

fn request_outgoing_payment_grant_section(
  client: client.Client,
  sender_address_info: WalletInfo,
  sender_address: String,
  quote: Quote,
  incoming_payment_id: String,
) -> Nil {
  section("Outgoing payment grant")

  // The grant must cover both outgoing payments: the quote's debit amount,
  // plus the 4999 spent directly against the incoming payment afterwards.
  let assert Ok(quote_debit_value) = int.parse(quote.debit_amount.value)
  let total_debit_amount =
    Amount(
      value: int.to_string(quote_debit_value + 4999),
      asset_code: quote.debit_amount.asset_code,
      asset_scale: quote.debit_amount.asset_scale,
    )
  let limits =
    Limits(
      receiver: Some(quote.receiver),
      amount: DebitAmount(total_debit_amount),
      interval: None,
    )
  let access =
    AccessOutgoing(
      actions: [OutgoingCreate, OutgoingRead, OutgoingReadAll, OutgoingList],
      identifier: sender_address,
      limits: Some(limits),
    )
  let interact =
    Interact(
      start: ["redirect"],
      finish: Some(Finish(
        method: "redirect",
        uri: "https://example.com/finish",
        nonce: "nonce",
      )),
    )
  let grant_options =
    GrantOptions(
      auth_server_url: sender_address_info.auth_server,
      access: [access],
      interact: Some(interact),
      address: sender_address,
    )

  case grants.request(client, grant_options) {
    Ok(grant) ->
      case grants.is_interactive_grant(grant) {
        True ->
          handle_pending_grant(client, grant, fn(token) {
            run_outgoing_payment_flow(
              client,
              sender_address_info,
              sender_address,
              token,
              quote.id,
              incoming_payment_id,
            )
          })
        False -> panic as "Grant should require interaction!"
      }
    Error(err) -> print_error("Failed to request grant", err)
  }
}

fn handle_pending_grant(
  client: client.Client,
  grant: GrantResponse,
  on_token: fn(AccessTokenResponse) -> Nil,
) -> Nil {
  case grant {
    PendingGrant(interact: interact, continue: continue) -> {
      io.println("  Status:   pending interaction")
      io.println("  Redirect: " <> interact.redirect)
      io.println("")
      let interact_ref = prompt("Paste the interact_ref once approved: ")

      case grants.continue(client, continue, interact_ref) {
        Ok(continuation) -> {
          print_continuation(continuation)
          case continuation.access_token {
            Some(token) -> on_token(token)
            None -> Nil
          }
        }
        Error(err) -> print_error("Failed to continue grant", err)
      }
    }
    Grant(..) -> panic as "Expected a pending grant"
  }
}

fn run_outgoing_payment_flow(
  client: client.Client,
  sender_address_info: WalletInfo,
  sender_address: String,
  access_token: AccessTokenResponse,
  quote_id: String,
  incoming_payment_id: String,
) -> Nil {
  case
    create_outgoing_payment_section(
      client,
      access_token.value,
      sender_address_info,
      sender_address,
      quote_id,
    )
  {
    Ok(payment) -> {
      list_outgoing_payments_section(
        client,
        access_token.value,
        sender_address_info,
        sender_address,
      )
      get_outgoing_payment_section(client, access_token.value, payment.id)

      // Fills up the remaining incoming payment amount, leaving 1 cent
      // unpaid, reusing the same access token from the grant above.
      let debit_amount =
        Amount(
          value: "4999",
          asset_code: sender_address_info.asset_code,
          asset_scale: sender_address_info.asset_scale,
        )
      case
        create_second_outgoing_payment_section(
          client,
          access_token.value,
          sender_address_info,
          sender_address,
          incoming_payment_id,
          debit_amount,
        )
      {
        Ok(second_payment) -> {
          get_outgoing_payment_section(
            client,
            access_token.value,
            second_payment.id,
          )
          wait_for_payments_section()
          get_outgoing_payment_grant_section(
            client,
            access_token.value,
            sender_address_info,
          )
          rotate_and_revoke_access_token_section(client, access_token)
        }
        Error(_) -> Nil
      }
    }
    Error(_) -> Nil
  }
}

fn wait_for_payments_section() -> Nil {
  section("Waiting for payments")

  io.println("  Waiting a few seconds for the payments to complete...")
  process.sleep(5000)
}

fn create_second_outgoing_payment_section(
  client: client.Client,
  access_token: String,
  address_info: WalletInfo,
  address: String,
  incoming_payment_id: String,
  debit_amount: Amount,
) -> Result(OutgoingPayment, OpenPaymentsError) {
  section("Create outgoing payment from incoming payment")

  let create_options =
    outgoing_payment.CreateOptions(
      resource_server: address_info.resource_server,
      wallet_address: address,
      source: FromIncomingPayment(
        incoming_payment: incoming_payment_id,
        debit_amount: debit_amount,
      ),
      metadata: None,
    )

  case outgoing_payment.create(client, access_token, create_options) {
    Ok(payment) -> {
      print_outgoing_payment(payment)
      Ok(payment)
    }
    Error(err) -> {
      print_error("Failed to create outgoing payment", err)
      Error(err)
    }
  }
}

fn create_outgoing_payment_section(
  client: client.Client,
  access_token: String,
  address_info: WalletInfo,
  address: String,
  quote_id: String,
) -> Result(OutgoingPayment, OpenPaymentsError) {
  section("Create outgoing payment")

  let create_options =
    outgoing_payment.CreateOptions(
      resource_server: address_info.resource_server,
      wallet_address: address,
      source: FromQuote(quote_id),
      metadata: None,
    )

  case outgoing_payment.create(client, access_token, create_options) {
    Ok(payment) -> {
      print_outgoing_payment(payment)
      Ok(payment)
    }
    Error(err) -> {
      print_error("Failed to create outgoing payment", err)
      Error(err)
    }
  }
}

fn list_outgoing_payments_section(
  client: client.Client,
  access_token: String,
  address_info: WalletInfo,
  address: String,
) -> Nil {
  section("List outgoing payments")

  let list_options =
    outgoing_payment.ListOptions(
      resource_server: address_info.resource_server,
      wallet_address: address,
      cursor: None,
      first: None,
      last: None,
    )

  case outgoing_payment.list(client, access_token, list_options) {
    Ok(payment_list) -> print_outgoing_payment_list(payment_list)
    Error(err) -> print_error("Failed to list outgoing payments", err)
  }
}

fn get_outgoing_payment_section(
  client: client.Client,
  access_token: String,
  payment_id: String,
) -> Nil {
  section("Get outgoing payment")

  case outgoing_payment.get(client, access_token, payment_id) {
    Ok(fetched) -> print_outgoing_payment(fetched)
    Error(err) -> print_error("Failed to get outgoing payment", err)
  }
}

fn get_outgoing_payment_grant_section(
  client: client.Client,
  access_token: String,
  address_info: WalletInfo,
) -> Nil {
  section("Outgoing payment grant spent amounts")

  case
    outgoing_payment.get_grant_spent_amounts(
      client,
      access_token,
      address_info.resource_server,
    )
  {
    Ok(spent) -> print_grant_spent_amounts(spent)
    Error(err) ->
      print_error("Failed to get outgoing payment grant spent amounts", err)
  }
}

fn rotate_and_revoke_access_token_section(
  client: client.Client,
  token: AccessTokenResponse,
) -> Nil {
  case rotate_access_token_section(client, token) {
    Ok(rotated) -> revoke_access_token_section(client, rotated)
    Error(_) -> Nil
  }
}

fn rotate_access_token_section(
  client: client.Client,
  token: AccessTokenResponse,
) -> Result(AccessTokenResponse, OpenPaymentsError) {
  section("Rotate access token")

  case access_token.rotate(client, token) {
    Ok(rotated) -> {
      field("Access token", rotated.value)
      field("Manage URL", rotated.manage)
      Ok(rotated)
    }
    Error(err) -> {
      print_error("Failed to rotate access token", err)
      Error(err)
    }
  }
}

fn revoke_access_token_section(
  client: client.Client,
  token: AccessTokenResponse,
) -> Nil {
  section("Revoke access token")

  case access_token.revoke(client, token) {
    Ok(_) -> io.println("  Access token revoked.")
    Error(err) -> print_error("Failed to revoke access token", err)
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

fn print_error(context: String, reason: OpenPaymentsError) -> Nil {
  io.println("  Error: " <> context <> " - " <> format_error(reason))
}

fn format_error(error: OpenPaymentsError) -> String {
  case error {
    TransportError(message) -> message
    ApiError(status: status, body: body) ->
      "server responded with " <> int.to_string(status) <> ": " <> body
    DecodeError(message) -> message
    KeyError(message) -> message
  }
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

fn format_amount_value(value: String, scale: Int) -> String {
  case scale <= 0 {
    True -> value
    False -> {
      let padded = string.pad_start(value, to: scale + 1, with: "0")
      let whole = string.slice(padded, 0, string.length(padded) - scale)
      let fraction = string.slice(padded, -scale, scale)
      whole <> "." <> fraction
    }
  }
}

fn print_amount(amount: Amount) -> String {
  format_amount_value(amount.value, amount.asset_scale)
  <> " "
  <> amount.asset_code
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

fn print_quote(quote: Quote) -> Nil {
  field("ID", quote.id)
  field("Wallet address", quote.wallet_address)
  field("Receiver", quote.receiver)
  field("Debit amount", print_amount(quote.debit_amount))
  field("Receive amount", print_amount(quote.receive_amount))
  field("Method", quote.method)
  field("Created at", quote.created_at)
}

fn print_outgoing_payment(payment: OutgoingPayment) -> Nil {
  field("ID", payment.id)
  field("Wallet address", payment.wallet_address)
  field("Receiver", payment.receiver)
  field("Debit amount", print_amount(payment.debit_amount))
  field("Receive amount", print_amount(payment.receive_amount))
  field("Sent amount", print_amount(payment.sent_amount))
  field("Failed", case payment.failed {
    True -> "yes"
    False -> "no"
  })
  field("Created at", payment.created_at)
}

fn print_grant_spent_amounts(spent: GrantSpentAmounts) -> Nil {
  case spent.spent_debit_amount {
    Some(amount) -> field("Spent debit amount", print_amount(amount))
    None -> field("Spent debit amount", "none")
  }
  case spent.spent_receive_amount {
    Some(amount) -> field("Spent receive amount", print_amount(amount))
    None -> field("Spent receive amount", "none")
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

fn print_outgoing_payment_list(payment_list: OutgoingPaymentList) -> Nil {
  field("Has next page", case payment_list.pagination.has_next_page {
    True -> "yes"
    False -> "no"
  })
  case payment_list.result {
    [] -> io.println("  (no outgoing payments found)")
    payments ->
      list.each(payments, fn(payment) {
        io.println(
          "  - "
          <> payment.id
          <> " (sent "
          <> print_amount(payment.sent_amount)
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
