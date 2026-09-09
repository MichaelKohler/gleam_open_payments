import gleam/dynamic/decode
import gleam/json
import gleam/result
import open_payments/request

pub type WalletInfo {
  WalletInfo(
    id: String,
    public_name: String,
    asset_code: String,
    asset_scale: Int,
    auth_server: String,
    resource_server: String,
  )
}

pub fn get(address: String) -> Result(WalletInfo, String) {
  let decoder = {
    use id <- decode.field("id", decode.string)
    use public_name <- decode.field("publicName", decode.string)
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

  use wallet_info <- result.try(request.send_unauthenticated_request(address))

  json.parse(wallet_info, decoder)
  |> result.map_error(fn(_) { "Failed to parse wallet info" })
}

// This might not be covering enough key types for all possible JWKS keys
pub type Key {
  Key(kid: String, x: String, alg: String, kty: String, crv: String)
}

pub fn get_keys(address: String) -> Result(List(Key), String) {
  let url = address <> "/jwks.json"
  use wallet_info <- result.try(request.send_unauthenticated_request(url))

  let key_decoder = {
    use kid <- decode.field("kid", decode.string)
    use x <- decode.field("x", decode.string)
    use alg <- decode.field("alg", decode.string)
    use kty <- decode.field("kty", decode.string)
    use crv <- decode.field("crv", decode.string)

    decode.success(Key(kid: kid, x: x, alg: alg, kty: kty, crv: crv))
  }

  let decoder = {
    use keys <- decode.field("keys", decode.list(key_decoder))

    decode.success(keys)
  }

  json.parse(wallet_info, decoder)
  |> result.map_error(fn(_) { "Failed to parse wallet keys" })
}
