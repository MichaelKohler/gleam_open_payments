-module(mock_server_ffi).
-export([listen/0, serve_one/2]).

listen() ->
    {ok, Socket} = gen_tcp:listen(
        0,
        [binary, {ip, {127, 0, 0, 1}}, {active, false}, {reuseaddr, true}, {packet, raw}]
    ),
    {ok, Port} = inet:port(Socket),
    {Socket, Port}.

serve_one(Socket, Response) ->
    {ok, Conn} = gen_tcp:accept(Socket),
    Request = read_head(Conn, <<>>),
    gen_tcp:send(Conn, Response),
    gen_tcp:close(Conn),
    gen_tcp:close(Socket),
    Request.

read_head(Conn, Acc) ->
    case binary:match(Acc, <<"\r\n\r\n">>) of
        {HeadEnd, _} ->
            HeadAndSep = HeadEnd + 4,
            Head = binary:part(Acc, 0, HeadAndSep),
            BodySoFar = binary:part(Acc, HeadAndSep, byte_size(Acc) - HeadAndSep),
            read_body(Conn, Head, BodySoFar, content_length(Head));
        nomatch ->
            case gen_tcp:recv(Conn, 0, 5000) of
                {ok, Data} -> read_head(Conn, <<Acc/binary, Data/binary>>);
                {error, _Reason} -> Acc
            end
    end.

read_body(_Conn, Head, BodySoFar, ContentLength) when byte_size(BodySoFar) >= ContentLength ->
    <<Head/binary, BodySoFar/binary>>;
read_body(Conn, Head, BodySoFar, ContentLength) ->
    case gen_tcp:recv(Conn, 0, 5000) of
        {ok, Data} -> read_body(Conn, Head, <<BodySoFar/binary, Data/binary>>, ContentLength);
        {error, _Reason} -> <<Head/binary, BodySoFar/binary>>
    end.

content_length(Head) ->
    Lines = binary:split(Head, <<"\r\n">>, [global]),
    find_content_length(Lines).

find_content_length([]) ->
    0;
find_content_length([Line | Rest]) ->
    LowerLine = string:lowercase(binary_to_list(Line)),
    case string:prefix(LowerLine, "content-length:") of
        nomatch -> find_content_length(Rest);
        ValueStr -> list_to_integer(string:trim(ValueStr))
    end.
