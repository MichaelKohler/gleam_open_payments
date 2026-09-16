import gleam/json
import gleam/option.{None, Some}
import open_payments/types.{
  AccessIncoming, AccessOutgoing, AccessQuote, Amount, DebitAmount,
  IncomingComplete, IncomingCreate, IncomingList, IncomingListAll, IncomingRead,
  IncomingReadAll, Limits, NoAmount, OutgoingCreate, OutgoingList,
  OutgoingListAll, OutgoingRead, OutgoingReadAll, PageInfo, QuoteCreate,
  QuoteRead, QuoteReadAll, ReceiveAmount,
}

pub fn encode_amount_test() {
  let amount = Amount("1000", "USD", 2)

  assert json.to_string(types.encode_amount(amount))
    == "{\"value\":\"1000\",\"assetCode\":\"USD\",\"assetScale\":2}"
}

pub fn decode_amount_round_trip_test() {
  let amount = Amount("1000", "USD", 2)

  assert json.parse(
      json.to_string(types.encode_amount(amount)),
      types.decode_amount(),
    )
    == Ok(amount)
}

pub fn decode_amount_option_no_amount_test() {
  assert json.parse("{}", types.decode_amount_option()) == Ok(NoAmount)
}

pub fn decode_amount_option_debit_amount_test() {
  let amount = Amount("1000", "USD", 2)
  let json_value = json.object([#("debitAmount", types.encode_amount(amount))])

  assert json.parse(json.to_string(json_value), types.decode_amount_option())
    == Ok(DebitAmount(amount))
}

pub fn decode_amount_option_receive_amount_test() {
  let amount = Amount("1000", "USD", 2)
  let json_value =
    json.object([#("receiveAmount", types.encode_amount(amount))])

  assert json.parse(json.to_string(json_value), types.decode_amount_option())
    == Ok(ReceiveAmount(amount))
}

pub fn add_amount_option_no_amount_test() {
  assert types.add_amount_option([], NoAmount) == []
}

pub fn add_amount_option_debit_amount_test() {
  let amount = Amount("1000", "USD", 2)

  assert types.add_amount_option([], DebitAmount(amount))
    == [#("debitAmount", types.encode_amount(amount))]
}

pub fn add_amount_option_receive_amount_test() {
  let amount = Amount("1000", "USD", 2)

  assert types.add_amount_option([], ReceiveAmount(amount))
    == [#("receiveAmount", types.encode_amount(amount))]
}

pub fn optional_field_none_test() {
  assert types.optional_field([], "name", None, json.string) == []
}

pub fn optional_field_some_test() {
  assert types.optional_field([], "name", Some("value"), json.string)
    == [#("name", json.string("value"))]
}

pub fn add_query_none_test() {
  assert types.add_query([], "cursor", None, fn(v) { v }) == []
}

pub fn add_query_some_test() {
  assert types.add_query([], "cursor", Some("abc"), fn(v) { v })
    == [#("cursor", "abc")]
}

pub fn decode_page_info_test() {
  let json_value =
    json.object([
      #("startCursor", json.string("start")),
      #("hasNextPage", json.bool(True)),
      #("hasPreviousPage", json.bool(False)),
    ])

  assert json.parse(json.to_string(json_value), types.decode_page_info())
    == Ok(PageInfo(Some("start"), None, True, False))
}

pub fn incoming_action_round_trip_test() {
  let decoder = types.decode_incoming_action()
  let encode = types.encode_incoming_action

  assert json.parse(json.to_string(encode(IncomingCreate)), decoder)
    == Ok(IncomingCreate)
  assert json.parse(json.to_string(encode(IncomingComplete)), decoder)
    == Ok(IncomingComplete)
  assert json.parse(json.to_string(encode(IncomingRead)), decoder)
    == Ok(IncomingRead)
  assert json.parse(json.to_string(encode(IncomingReadAll)), decoder)
    == Ok(IncomingReadAll)
  assert json.parse(json.to_string(encode(IncomingList)), decoder)
    == Ok(IncomingList)
  assert json.parse(json.to_string(encode(IncomingListAll)), decoder)
    == Ok(IncomingListAll)
}

pub fn outgoing_action_round_trip_test() {
  let decoder = types.decode_outgoing_action()
  let encode = types.encode_outgoing_action

  assert json.parse(json.to_string(encode(OutgoingCreate)), decoder)
    == Ok(OutgoingCreate)
  assert json.parse(json.to_string(encode(OutgoingRead)), decoder)
    == Ok(OutgoingRead)
  assert json.parse(json.to_string(encode(OutgoingReadAll)), decoder)
    == Ok(OutgoingReadAll)
  assert json.parse(json.to_string(encode(OutgoingList)), decoder)
    == Ok(OutgoingList)
  assert json.parse(json.to_string(encode(OutgoingListAll)), decoder)
    == Ok(OutgoingListAll)
}

pub fn quote_action_round_trip_test() {
  let decoder = types.decode_quote_action()
  let encode = types.encode_quote_action

  assert json.parse(json.to_string(encode(QuoteCreate)), decoder)
    == Ok(QuoteCreate)
  assert json.parse(json.to_string(encode(QuoteRead)), decoder) == Ok(QuoteRead)
  assert json.parse(json.to_string(encode(QuoteReadAll)), decoder)
    == Ok(QuoteReadAll)
}

pub fn encode_decode_limits_test() {
  let limits =
    Limits(
      receiver: Some("https://wallet.example/receiver"),
      interval: Some("R/2024-01-01T00:00:00Z/P1M"),
      amount: DebitAmount(Amount("500", "USD", 2)),
    )

  assert json.parse(
      json.to_string(types.encode_limits(limits)),
      types.decode_limits(),
    )
    == Ok(limits)
}

pub fn encode_decode_limits_without_optionals_test() {
  let limits = Limits(receiver: None, interval: None, amount: NoAmount)

  assert json.parse(
      json.to_string(types.encode_limits(limits)),
      types.decode_limits(),
    )
    == Ok(limits)
}

pub fn encode_decode_access_incoming_test() {
  let access =
    AccessIncoming(
      actions: [IncomingCreate, IncomingRead],
      identifier: Some("https://wallet.example/receiver"),
    )

  assert json.parse(
      json.to_string(types.encode_access(access)),
      types.decode_access(),
    )
    == Ok(access)
}

pub fn encode_decode_access_outgoing_test() {
  let access =
    AccessOutgoing(
      actions: [OutgoingCreate, OutgoingRead],
      identifier: "https://wallet.example/sender",
      limits: Some(Limits(None, None, DebitAmount(Amount("500", "USD", 2)))),
    )

  assert json.parse(
      json.to_string(types.encode_access(access)),
      types.decode_access(),
    )
    == Ok(access)
}

pub fn encode_decode_access_quote_test() {
  let access = AccessQuote(actions: [QuoteCreate, QuoteRead])

  assert json.parse(
      json.to_string(types.encode_access(access)),
      types.decode_access(),
    )
    == Ok(access)
}

pub fn decode_access_token_response_test() {
  let json_value =
    json.object([
      #("value", json.string("token-value")),
      #("manage", json.string("https://auth.example/token/abc")),
      #("expires_in", json.int(3600)),
      #("access", json.array([AccessQuote([QuoteCreate])], types.encode_access)),
    ])

  assert json.parse(
      json.to_string(json_value),
      types.decode_access_token_response(),
    )
    == Ok(
      types.AccessTokenResponse(
        value: "token-value",
        manage: "https://auth.example/token/abc",
        expires_in: Some(3600),
        access: [AccessQuote([QuoteCreate])],
      ),
    )
}
