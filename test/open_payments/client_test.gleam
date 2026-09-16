import open_payments/client.{AuthenticatedClient}
import simplifile

pub fn create_test() {
  let assert Ok(private_key) = simplifile.read("test/fixtures/private_key")

  let created =
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
