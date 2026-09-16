import gleam/result
import gleam/string
import http_message_signatures/keys.{type PrivateKey}
import open_payments/error.{type OpenPaymentsError, KeyError}
import simplifile

/// Holds the credentials used to sign requests to the Open Payments auth and
/// resource servers on behalf of a wallet address.
pub type Client {
  AuthenticatedClient(
    wallet_address_url: String,
    private_key: PrivateKey,
    key_id: String,
  )
}

/// Creates a `Client` for the given wallet address, reading and parsing the
/// Ed25519 private key used for HTTP message signatures from
/// `private_key_path`. `key_id` must match the ID of the corresponding
/// public key registered on the wallet address.
///
/// Returns `Error(KeyError(_))` if the key file can't be read or doesn't
/// contain a valid PKCS#8 PEM-encoded Ed25519 private key.
pub fn create(
  wallet_address_url wallet_address_url: String,
  key_id key_id: String,
  private_key_path private_key_path: String,
) -> Result(Client, OpenPaymentsError) {
  use private_key <- result.try(read_private_key(private_key_path))

  Ok(AuthenticatedClient(wallet_address_url, private_key, key_id))
}

fn read_private_key(path: String) -> Result(PrivateKey, OpenPaymentsError) {
  use pem <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(err) {
      KeyError(
        "Failed to read private key file at "
        <> path
        <> ": "
        <> string.inspect(err),
      )
    }),
  )

  keys.key_pair_from_pem(pem)
  |> result.map(fn(pair) { pair.0 })
  |> result.map_error(fn(err) {
    KeyError(
      "Failed to parse private key at " <> path <> ": " <> string.inspect(err),
    )
  })
}
