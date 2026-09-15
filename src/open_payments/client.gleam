import simplifile

pub type Client {
  AuthenticatedClient(
    wallet_address_url: String,
    private_key: String,
    key_id: String,
  )
}

pub fn create(
  wallet_address_url wallet_address_url: String,
  key_id key_id: String,
  private_key_path private_key_path: String,
) -> Client {
  let private_key = read_private_key(private_key_path)

  AuthenticatedClient(wallet_address_url, private_key, key_id)
}

fn read_private_key(path: String) -> String {
  let assert Ok(private_key) = simplifile.read(path)
  private_key
}
