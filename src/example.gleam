import gleam/io
import gleam/string
import open_payments/client
import open_payments/wallet_address

pub fn main() -> Nil {
  // let client = client.create("https://ilp.interledger-test.dev/michaelusd", "1", "../fixtures/private-key")

  let address = "https://ilp.interledger-test.dev/michaeleur"
  let address_info = wallet_address.get(address)

  case address_info {
    Ok(info) -> io.println("Wallet address info: " <> string.inspect(info))
    Error(err) -> io.println("Failed to get wallet address info: " <> err)
  }

  let keys = wallet_address.get_keys(address)

  case keys {
    Ok(keys) -> io.println("Keys: " <> string.inspect(keys))
    Error(err) -> io.println("Failed to get keys: " <> err)
  }
}
