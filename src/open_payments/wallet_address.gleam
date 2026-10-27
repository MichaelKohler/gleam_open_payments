import gleam/dynamic/decode
import gleam/option.{type Option, None, Some}
import open_payments/error.{type OpenPaymentsError}
import open_payments/request
import open_payments/types.{type Key, Key}

/// The public details of a wallet address, as returned by `get`.
/// See https://openpayments.dev/apis/wallet-address-server/operations/get-wallet-address/
pub type WalletInfo {
  WalletInfo(
    id: String,
    public_name: Option(String),
    asset_code: String,
    asset_scale: Int,
    auth_server: String,
    resource_server: String,
  )
}

@internal
pub fn decode_wallet_info() -> decode.Decoder(WalletInfo) {
  use id <- decode.field("id", decode.string)
  use public_name <- decode.optional_field(
    "publicName",
    None,
    decode.string |> decode.map(Some),
  )
  use asset_code <- decode.field("assetCode", decode.string)
  use asset_scale <- decode.field("assetScale", decode.int)
  use auth_server <- decode.field("authServer", decode.string)
  use resource_server <- decode.field("resourceServer", decode.string)

  decode.success(WalletInfo(
    id: id,
    public_name: public_name,
    asset_code: asset_code,
    asset_scale: asset_scale,
    auth_server: auth_server,
    resource_server: resource_server,
  ))
}

@internal
pub fn decode_key() -> decode.Decoder(Key) {
  use kid <- decode.field("kid", decode.string)
  use x <- decode.field("x", decode.string)
  use _ <- decode.field("alg", decode_exactly("EdDSA"))
  use _ <- decode.field("kty", decode_exactly("OKP"))
  use _ <- decode.field("crv", decode_exactly("Ed25519"))
  use _ <- decode.optional_field("use", "sig", decode_exactly("sig"))

  decode.success(Key(kid: kid, x: x))
}

fn decode_exactly(expected: String) -> decode.Decoder(String) {
  use value <- decode.then(decode.string)
  case value == expected {
    True -> decode.success(value)
    False -> decode.failure(value, expected)
  }
}

@internal
pub fn decode_keys() -> decode.Decoder(List(Key)) {
  use keys <- decode.field("keys", decode.list(decode_key()))

  decode.success(keys)
}

/// Fetches the public details of the wallet address, including the auth
/// and resource server URLs needed for further requests.
/// See https://openpayments.dev/apis/wallet-address-server/operations/get-wallet-address/
pub fn get(address: String) -> Result(WalletInfo, OpenPaymentsError) {
  request.send_unauthenticated_and_decode(
    address,
    decoder: decode_wallet_info(),
    error_context: "Failed to parse wallet info",
  )
}

/// Fetches the public keys (JWKS) registered on the wallet address, used to
/// verify signatures made by its owner.
/// See https://openpayments.dev/apis/wallet-address-server/operations/get-wallet-address-keys/
pub fn get_keys(address: String) -> Result(List(Key), OpenPaymentsError) {
  let url = address <> "/jwks.json"

  request.send_unauthenticated_and_decode(
    url,
    decoder: decode_keys(),
    error_context: "Failed to parse wallet keys",
  )
}
