import envoy
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

pub fn create_from_pem_test() {
  let assert Ok(pem) = simplifile.read("test/fixtures/private_key")
  let assert Ok(#(private_key, _public_key)) = keys.key_pair_from_pem(pem)

  let assert Ok(created) =
    client.create_from_pem(
      wallet_address_url: "https://ilp.interledger-test.dev/michaelusd",
      key_id: "be52ffa9-b61b-4a8c-8dbe-43b75cda31c9",
      private_key_pem: pem,
    )

  assert created
    == AuthenticatedClient(
      wallet_address_url: "https://ilp.interledger-test.dev/michaelusd",
      private_key: private_key,
      key_id: "be52ffa9-b61b-4a8c-8dbe-43b75cda31c9",
    )
}

pub fn create_from_pem_invalid_key_test() {
  let assert Error(KeyError(message)) =
    client.create_from_pem(
      wallet_address_url: "https://ilp.interledger-test.dev/michaelusd",
      key_id: "be52ffa9-b61b-4a8c-8dbe-43b75cda31c9",
      private_key_pem: "not a valid PEM",
    )

  assert string.contains(message, "Failed to parse")
}

pub fn create_from_env_test() {
  let assert Ok(pem) = simplifile.read("test/fixtures/private_key")
  let assert Ok(#(private_key, _public_key)) = keys.key_pair_from_pem(pem)
  envoy.set("OPEN_PAYMENTS_TEST_PRIVATE_KEY", pem)

  let assert Ok(created) =
    client.create_from_env(
      wallet_address_url: "https://ilp.interledger-test.dev/michaelusd",
      key_id: "be52ffa9-b61b-4a8c-8dbe-43b75cda31c9",
      private_key_env_var: "OPEN_PAYMENTS_TEST_PRIVATE_KEY",
    )
  envoy.unset("OPEN_PAYMENTS_TEST_PRIVATE_KEY")

  assert created
    == AuthenticatedClient(
      wallet_address_url: "https://ilp.interledger-test.dev/michaelusd",
      private_key: private_key,
      key_id: "be52ffa9-b61b-4a8c-8dbe-43b75cda31c9",
    )
}

pub fn create_from_env_unset_test() {
  envoy.unset("OPEN_PAYMENTS_TEST_UNSET_KEY")

  let assert Error(KeyError(message)) =
    client.create_from_env(
      wallet_address_url: "https://ilp.interledger-test.dev/michaelusd",
      key_id: "be52ffa9-b61b-4a8c-8dbe-43b75cda31c9",
      private_key_env_var: "OPEN_PAYMENTS_TEST_UNSET_KEY",
    )

  assert message
    == "Environment variable OPEN_PAYMENTS_TEST_UNSET_KEY is not set"
}

pub fn create_from_env_invalid_key_test() {
  envoy.set("OPEN_PAYMENTS_TEST_INVALID_KEY", "not a valid PEM")

  let assert Error(KeyError(message)) =
    client.create_from_env(
      wallet_address_url: "https://ilp.interledger-test.dev/michaelusd",
      key_id: "be52ffa9-b61b-4a8c-8dbe-43b75cda31c9",
      private_key_env_var: "OPEN_PAYMENTS_TEST_INVALID_KEY",
    )
  envoy.unset("OPEN_PAYMENTS_TEST_INVALID_KEY")

  assert string.contains(
    message,
    "Failed to parse private key from environment variable OPEN_PAYMENTS_TEST_INVALID_KEY",
  )
  assert !string.contains(message, "not a valid PEM")
}
