# Gleam Open Payment SDK

[![Package Version](https://img.shields.io/hexpm/v/open_payments)](https://hex.pm/packages/open_payments)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://open-payments-sdk.hexdocs.pm/)

[Open Payments](https://openpayments.dev/) SDK for Gleam.

```sh
gleam add open_payments@1
```

```gleam
import gleam/io
import gleam/option.{None, Some}
import open_payments/client
import open_payments/grants.{Grant, GrantOptions}
import open_payments/incoming_payment
import open_payments/quotes
import open_payments/types.{
  AccessIncoming, AccessQuote, Amount, DebitAmount, IncomingCreate, QuoteCreate,
}
import open_payments/wallet_address

pub fn main() -> Nil {
  let assert Ok(client) =
    client.create(
      "https://ilp.interledger-test.dev/michaelusd",
      "be52ffa9-b61b-4a8c-8dbe-43b75cda31c9",
      "fixtures/private_key",
    )
  let sender_address = "https://ilp.interledger-test.dev/michaelusd"
  let receiver_address = "https://ilp.interledger-test.dev/michaeleur"

  let assert Ok(receiver_info) = wallet_address.get(receiver_address)
  let assert Ok(sender_info) = wallet_address.get(sender_address)

  let incoming_grant_options =
    GrantOptions(
      receiver_info.auth_server,
      AccessIncoming([IncomingCreate], Some(receiver_address)),
      None,
      receiver_address,
    )
  let assert Ok(Grant(access_token: incoming_token, continue: _)) =
    grants.request(client, incoming_grant_options)

  let incoming_payment_options =
    incoming_payment.CreateOptions(
      resource_server: receiver_info.resource_server,
      wallet_address: receiver_address,
      incoming_amount: Some(Amount(
        "10000",
        receiver_info.asset_code,
        receiver_info.asset_scale,
      )),
      expires_at: None,
      metadata: None,
    )
  let assert Ok(payment) =
    incoming_payment.create(
      client,
      incoming_token.value,
      incoming_payment_options,
    )
  io.debug(payment)

  Nil
}
```

Note that this example only creates an incoming payment, and no outgoing payment. Check the `sdk_example.gleam` file for a full end-to-end example.

Further documentation can be found at <https://open-payments.hexdocs.pm/>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```

Running `gleam run -m sdk_example` executes `src/sdk_example.gleam`, which sends signed
requests against a real Open Payments wallet, so it needs credentials for a
wallet you control:

- Create `fixtures/private_key` (git-ignored, not committed) with the PEM
  private key matching a public key registered on your wallet address.
- In `src/sdk_example.gleam`, update the wallet address and key ID passed to
  `client.create` to match your own wallet address and the ID of the key you
  registered there — the ones currently in the file are specific to the
  original author's test wallet and will fail signature verification for
  anyone else.

## Missing scope

- Grant request with subject
- Testing grant request with directed identity
