# Gleam Open Payment SDK

[![Package Version](https://img.shields.io/hexpm/v/open_payments)](https://hex.pm/packages/open_payments)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://open-payments-sdk.hexdocs.pm/)

[Open Payments](https://openpayments.dev/) SDK for Gleam.

```sh
gleam add open_payments@1
```

```gleam
import open_payments

pub fn main() -> Nil {
  // TODO: An example of the project in use
}
```

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
