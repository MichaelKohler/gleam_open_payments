import envoy
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
  use pem <- result.try(
    simplifile.read(private_key_path)
    |> result.map_error(fn(err) {
      KeyError(
        "Failed to read private key file at "
        <> private_key_path
        <> ": "
        <> string.inspect(err),
      )
    }),
  )

  create_with_key(wallet_address_url, key_id, pem, "at " <> private_key_path)
}

/// Creates a `Client` for the given wallet address from the Ed25519 private
/// key in `private_key_pem`, a PKCS#8 PEM string. Use this when the key comes
/// from somewhere other than a file, such as a secret manager. `key_id` must
/// match the ID of the corresponding public key registered on the wallet
/// address.
///
/// Returns `Error(KeyError(_))` if `private_key_pem` isn't a valid PKCS#8
/// PEM-encoded Ed25519 private key.
pub fn create_from_pem(
  wallet_address_url wallet_address_url: String,
  key_id key_id: String,
  private_key_pem private_key_pem: String,
) -> Result(Client, OpenPaymentsError) {
  create_with_key(wallet_address_url, key_id, private_key_pem, "from PEM")
}

/// Creates a `Client` for the given wallet address, reading the Ed25519
/// private key as a PKCS#8 PEM string from the environment variable named
/// `private_key_env_var`. The variable must hold the PEM itself, with its
/// line breaks, not a path to a key file. `key_id` must match the ID of the
/// corresponding public key registered on the wallet address.
///
/// Returns `Error(KeyError(_))` if the environment variable isn't set or
/// doesn't hold a valid PKCS#8 PEM-encoded Ed25519 private key.
pub fn create_from_env(
  wallet_address_url wallet_address_url: String,
  key_id key_id: String,
  private_key_env_var private_key_env_var: String,
) -> Result(Client, OpenPaymentsError) {
  use pem <- result.try(
    envoy.get(private_key_env_var)
    |> result.replace_error(KeyError(
      "Environment variable " <> private_key_env_var <> " is not set",
    )),
  )

  create_with_key(
    wallet_address_url,
    key_id,
    pem,
    "from environment variable " <> private_key_env_var,
  )
}

/// Parses `pem` and builds the `Client`. `source` says where the key came
/// from, for the error message, and never includes the key itself.
fn create_with_key(
  wallet_address_url: String,
  key_id: String,
  pem: String,
  source: String,
) -> Result(Client, OpenPaymentsError) {
  use private_key <- result.try(
    keys.key_pair_from_pem(pem)
    |> result.map(fn(pair) { pair.0 })
    |> result.map_error(fn(err) {
      KeyError(
        "Failed to parse private key " <> source <> ": " <> string.inspect(err),
      )
    }),
  )

  Ok(AuthenticatedClient(wallet_address_url, private_key, key_id))
}
