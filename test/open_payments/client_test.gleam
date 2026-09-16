import gleam/string
import http_message_signatures/keys
import open_payments/client.{AuthenticatedClient}
import open_payments/error.{KeyError}
import simplifile

pub fn create_test() {
  let assert Ok(pem) = simplifile.read("test/fixtures/private_key")
  let assert Ok(#(private_key, _public_key)) = keys.key_pair_from_pem(pem)

  let assert Ok(created) =
    client.create(
      wallet_address_url: "https://ilp.interledger-test.dev/michaelusd",
      key_id: "be52ffa9-b61b-4a8c-8dbe-43b75cda31c9",
      private_key_path: "test/fixtures/private_key",
    )

  assert created
    == AuthenticatedClient(
      wallet_address_url: "https://ilp.interledger-test.dev/michaelusd",
      private_key: private_key,
      key_id: "be52ffa9-b61b-4a8c-8dbe-43b75cda31c9",
    )
}

pub fn create_missing_file_test() {
  let assert Error(KeyError(message)) =
    client.create(
      wallet_address_url: "https://ilp.interledger-test.dev/michaelusd",
      key_id: "be52ffa9-b61b-4a8c-8dbe-43b75cda31c9",
      private_key_path: "test/fixtures/does_not_exist",
    )

  assert string.contains(message, "Failed to read")
}

pub fn create_invalid_key_test() {
  let assert Error(KeyError(message)) =
    client.create(
      wallet_address_url: "https://ilp.interledger-test.dev/michaelusd",
      key_id: "be52ffa9-b61b-4a8c-8dbe-43b75cda31c9",
      private_key_path: "test/fixtures/invalid_private_key",
    )

  assert string.contains(message, "Failed to parse")
}
