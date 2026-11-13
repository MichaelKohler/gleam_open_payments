//// Helpers shared by the SDK's modules for building request bodies, URLs and
//// query strings. This module is internal to the package: it is left out of
//// the documentation and isn't part of the public API.

import gleam/int
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import gleam/string
import open_payments/error.{type OpenPaymentsError, ValidationError}

/// The page size bounds for `first` and `last`, per the Open Payments spec.
const min_page_size = 1

const max_page_size = 100

/// Prepends `#(name, encode(v))` to `fields` when `value` is `Some(v)`,
/// otherwise leaves `fields` unchanged. Used to build JSON objects with
/// optional fields.
pub fn optional_field(
  fields: List(#(String, Json)),
  name: String,
  value: Option(a),
  encode: fn(a) -> Json,
) -> List(#(String, Json)) {
  case value {
    Some(v) -> [#(name, encode(v)), ..fields]
    None -> fields
  }
}

/// Prepends `#(name, value)` to `query` when `value` is `Some(v)`, otherwise
/// leaves `query` unchanged. Used to build query strings with optional
/// parameters.
pub fn add_query(
  query: List(#(String, String)),
  name: String,
  value: Option(a),
  encode: fn(a) -> String,
) -> List(#(String, String)) {
  case value {
    Some(v) -> [#(name, encode(v)), ..query]
    None -> query
  }
}

/// Appends `path`, which starts with `/`, to `base`, dropping any trailing
/// slashes from `base` first. Servers may return their URLs with a trailing
/// slash, and joining those as-is would produce a `//` in the path.
pub fn join_url(base: String, path: String) -> String {
  case string.ends_with(base, "/") {
    True -> join_url(string.drop_end(base, 1), path)
    False -> base <> path
  }
}

/// Rejects pagination parameters the Open Payments spec forbids: `first`
/// and `last` together, `last` without a `cursor`, or a page size outside
/// 1 to 100.
pub fn validate_pagination(
  cursor cursor: Option(String),
  first first: Option(Int),
  last last: Option(Int),
) -> Result(Nil, OpenPaymentsError) {
  case cursor, first, last {
    _, Some(_), Some(_) ->
      Error(ValidationError("Pagination cannot use both first and last"))
    None, _, Some(_) ->
      Error(ValidationError("Pagination with last requires a cursor"))
    _, Some(size), _
    | _, _, Some(size)
      if size < min_page_size || size > max_page_size
    ->
      Error(ValidationError(
        "Pagination page size must be between "
        <> int.to_string(min_page_size)
        <> " and "
        <> int.to_string(max_page_size),
      ))
    _, _, _ -> Ok(Nil)
  }
}
