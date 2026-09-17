import http_message_signatures/keys
import open_payments/client.{type Client, AuthenticatedClient}
import simplifile

/// Builds a real `Client` from the Ed25519 test key fixture, for tests that
/// need to send signed requests without going over the network.
pub fn client() -> Client {
  let assert Ok(pem) = simplifile.read("test/fixtures/private_key")
  let assert Ok(#(private_key, _public_key)) = keys.key_pair_from_pem(pem)

  AuthenticatedClient(
    wallet_address_url: "https://ilp.interledger-test.dev/michaelusd",
    private_key: private_key,
    key_id: "be52ffa9-b61b-4a8c-8dbe-43b75cda31c9",
  )
}
