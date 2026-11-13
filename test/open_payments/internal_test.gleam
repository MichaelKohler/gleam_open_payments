import gleam/json
import gleam/option.{None, Some}
import open_payments/error.{ValidationError}
import open_payments/internal

pub fn optional_field_none_test() {
  assert internal.optional_field([], "name", None, json.string) == []
}

pub fn optional_field_some_test() {
  assert internal.optional_field([], "name", Some("value"), json.string)
    == [#("name", json.string("value"))]
}

pub fn join_url_test() {
  assert internal.join_url("https://resource.example", "/quotes")
    == "https://resource.example/quotes"
}

pub fn join_url_trailing_slash_test() {
  assert internal.join_url("https://resource.example/", "/quotes")
    == "https://resource.example/quotes"
}

pub fn join_url_multiple_trailing_slashes_test() {
  assert internal.join_url("https://resource.example//", "/quotes")
    == "https://resource.example/quotes"
}

pub fn add_query_none_test() {
  assert internal.add_query([], "cursor", None, fn(v) { v }) == []
}

pub fn add_query_some_test() {
  assert internal.add_query([], "cursor", Some("abc"), fn(v) { v })
    == [#("cursor", "abc")]
}

pub fn validate_pagination_none_test() {
  assert internal.validate_pagination(cursor: None, first: None, last: None)
    == Ok(Nil)
}

pub fn validate_pagination_first_bounds_test() {
  assert internal.validate_pagination(cursor: None, first: Some(1), last: None)
    == Ok(Nil)
  assert internal.validate_pagination(
      cursor: None,
      first: Some(100),
      last: None,
    )
    == Ok(Nil)
  assert internal.validate_pagination(cursor: None, first: Some(0), last: None)
    == Error(ValidationError("Pagination page size must be between 1 and 100"))
  assert internal.validate_pagination(
      cursor: None,
      first: Some(101),
      last: None,
    )
    == Error(ValidationError("Pagination page size must be between 1 and 100"))
}

pub fn validate_pagination_last_bounds_test() {
  assert internal.validate_pagination(
      cursor: Some("c"),
      first: None,
      last: Some(1),
    )
    == Ok(Nil)
  assert internal.validate_pagination(
      cursor: Some("c"),
      first: None,
      last: Some(100),
    )
    == Ok(Nil)
  assert internal.validate_pagination(
      cursor: Some("c"),
      first: None,
      last: Some(0),
    )
    == Error(ValidationError("Pagination page size must be between 1 and 100"))
  assert internal.validate_pagination(
      cursor: Some("c"),
      first: None,
      last: Some(101),
    )
    == Error(ValidationError("Pagination page size must be between 1 and 100"))
}

pub fn validate_pagination_first_and_last_test() {
  assert internal.validate_pagination(
      cursor: Some("c"),
      first: Some(5),
      last: Some(5),
    )
    == Error(ValidationError("Pagination cannot use both first and last"))
}

pub fn validate_pagination_last_without_cursor_test() {
  assert internal.validate_pagination(cursor: None, first: None, last: Some(5))
    == Error(ValidationError("Pagination with last requires a cursor"))
}

pub fn validate_pagination_first_with_cursor_test() {
  assert internal.validate_pagination(
      cursor: Some("c"),
      first: Some(5),
      last: None,
    )
    == Ok(Nil)
}
