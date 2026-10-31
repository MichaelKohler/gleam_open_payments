# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

This release aligns the SDK with the Open Payments API specification (v1.4.1).

### Changed

- **Breaking:** `PublicIncomingPayment` has new fields from the specification:
  `id`, `completed`, `incoming_amount`, `expires_at`, `created_at` and
  `methods`. Resource servers don't send most of these yet, so they are optional
  for now, even where the specification requires them, and `methods` is empty
  when it's missing.

## [2.0.0] - 2026-10-27

This release aligns the SDK with the Open Payments API specification (v1.4.0).
It contains breaking changes; see [Migrating from 1.x](#migrating-from-1x).

### Added

- `incoming_payment.get_public` fetches the public view of an incoming payment
  (`PublicIncomingPayment`) without an access token or request signature.
- `ClientWalletAddressString` sends the client as a bare wallet address string,
  the form the spec has deprecated, for auth servers that don't yet accept the
  object form.
- `ApiError` now carries the parsed `error` body as a `ServerError` (with an
  `ErrorCode` such as `TooFast` or `InvalidContinuation`), and the `as_uri`
  from a resource server's `WWW-Authenticate: GNAP as_uri=...` header.
- `ValidationError` is returned, without sending the request, when the options
  break a rule of the spec:
  - a grant request with neither access items nor a subject;
  - a grant request with a subject but no `interact`;
  - a directed identity (`jwk`) client combined with `interact`;
  - more than 3 access items, duplicate access items, or duplicate actions;
  - list pagination with both `first` and `last`, `last` without a `cursor`,
    or a page size outside 1 to 100.
- `AccessOther`, `IncomingOther`, `OutgoingOther` and `QuoteOther` keep access
  types and actions this SDK doesn't know yet, instead of failing to decode the
  whole response.
- `quotes.PaymentMethod` (`Ilp`), used by `quotes.CreateOptions` and `Quote`.
- `grants.StartMode` (`StartRedirect`) and `grants.FinishMethod`
  (`FinishRedirect`) for the grant `interact` options.

### Changed

- **Breaking:** `ClientWalletAddressObject` is now sent as
  `{"walletAddress": ...}` rather than a bare string. This is also the default
  when `GrantOptions.client_type` is `None`.
- **Breaking:** `grants.continue` takes `interact_ref` as an `Option(String)`.
  Pass `None` to poll a pending grant, which sends the request without a body.
- **Breaking:** `GrantOptions.subject` is now an `Option(SubjectId)`, since
  the spec allows exactly one subject identifier. `Subject` is still used in
  continuation responses.
- **Breaking:** `ApiError` has two new fields, `error` and `as_uri`.
- **Breaking:** `OpenPaymentsError` has a new `ValidationError` variant.
- **Breaking:** `Key` only holds `kid` and `x`. The fixed Ed25519 members
  (`alg`, `kty`, `crv` and `use`) are written when encoding and checked when
  decoding.
- **Breaking:** `WalletInfo.public_name` is now an `Option(String)`, as the
  spec doesn't require it.
- **Breaking:** `Interact.start` is a `List(StartMode)` and `Finish.method` is
  a `FinishMethod`, rather than strings.
- **Breaking:** `Quote.method` is a `PaymentMethod` rather than a string, and
  `quotes.CreateOptions` has a new `method` field.
- **Breaking:** the request helpers in `open_payments/request`, the
  JSON/query helpers in `open_payments/types`, and `grants.Body` /
  `grants.AccessTokenBodyProperty` are now internal and no longer part of the
  public API.
- `wallet_address.get_keys` skips keys that aren't Ed25519 signing keys rather
  than failing on the whole key set.

### Removed

- **Breaking:** `GrantOptions.address`, which was never used.

### Migrating from 1.x

- Remove `address:` from every `GrantOptions`.
- Replace `subject: Some(Subject(sub_ids: [id]))` with `subject: Some(id)`.
- Pass `Some(interact_ref)` to `grants.continue`.
- Replace `Interact(start: ["redirect"], ...)` with
  `Interact(start: [StartRedirect], ...)`, and `Finish(method: "redirect", ...)`
  with `Finish(method: FinishRedirect, ...)`.
- Construct keys as `Key(kid:, x:)`.
- Add `method: Ilp` to `quotes.CreateOptions`.
- Handle `public_name` as an `Option(String)`.
- Match `ApiError(status:, body:, ..)` and handle `ValidationError` in
  exhaustive `case` expressions on `OpenPaymentsError`.
- If your auth server only accepts the string form of `client`, pass
  `client_type: Some(ClientWalletAddressString(wallet_address))`.

## [1.1.0] - 2026-09-18

### Added

- Grant requests can ask for subject information (`GrantOptions.subject`), and
  continuation responses return it (`ContinuationResponse.subject`).
- A grant request may leave `access` empty for a subject-only request.

## [1.0.0] - 2026-09-17

### Added

- Initial release: wallet address details and keys, grant requests,
  continuation and cancellation, access token rotation and revocation,
  incoming payments, outgoing payments, quotes and outgoing payment grant spent
  amounts, with signed requests.

[Unreleased]: https://github.com/MichaelKohler/gleam_open_payments/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/MichaelKohler/gleam_open_payments/compare/v1.0.1...v2.0.0
[1.1.0]: https://github.com/MichaelKohler/gleam_open_payments/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/MichaelKohler/gleam_open_payments/releases/tag/v1.0.0
