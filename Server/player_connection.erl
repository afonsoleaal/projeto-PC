-module(player_connection).
-export([start/1, stop/1]).

start(Socket) ->
    Pid = spawn(fun() -> init(Socket) end),
    gen_tcp:controlling_process(Socket, Pid),
    {ok, Pid}.

stop(Pid) -> Pid ! stop, ok.

init(Socket) ->
    inet:setopts(Socket, [{active, once}, {packet, raw}, binary]),
    State = #{socket => Socket, username => undefined, game_room => undefined},
    loop(State).

loop(State = #{socket := Socket, game_room := GameRoomPid}) ->
    receive
        {tcp, Socket, BinaryData} ->
            NewState = handle_binary_payload(BinaryData, State),
            inet:setopts(Socket, [{active, once}]),
            loop(NewState);

        {tcp_closed, Socket} ->
            io:format("Client disconnected.~n"),
            if GameRoomPid =/= undefined -> 
                   GameRoomPid ! {player_left, self()};
               true -> 
                   matchmaker:leave(self())
            end,
            ok;

        {tcp_error, Socket, Reason} ->
            io:format("TCP Error: ~p~n", [Reason]),
            ok;
        
        {game_started, RoomPid, PlayerId, MapWidth, MapHeight} ->
            io:format("Game Started! My Player ID is ~p~n", [PlayerId]),
            
            Packet = <<18:8, PlayerId:32/integer, MapWidth:32/float, MapHeight:32/float>>,
            gen_tcp:send(Socket, Packet),
            
            loop(State#{game_room => RoomPid});

        {send_raw_packet, Packet} ->
            gen_tcp:send(Socket, Packet),
            loop(State);

        stop ->
            gen_tcp:close(Socket),
            Username = maps:get(username, State),
            if Username =/= undefined -> account_manager:logout(account_manager, Username);
                true -> ok
            end,
            ok;

        _Unknown ->
            loop(State)
    end.

handle_binary_payload(<<>>, State) ->
    State;

handle_binary_payload(<<1:8, UserLen:16, UserBin:UserLen/binary, PassLen:16, PassBin:PassLen/binary, Rest/binary>>, State = #{socket := Socket}) ->
    Username = binary_to_list(UserBin),
    Password = binary_to_list(PassBin),
    case account_manager:register(account_manager, Username, Password) of
        ok -> send_auth_response(Socket, 1, "Registered successfully.");
        {error, _} -> send_auth_response(Socket, 0, "Username already exists.")
    end,
    handle_binary_payload(Rest, State);

handle_binary_payload(<<2:8, UserLen:16, UserBin:UserLen/binary, PassLen:16, PassBin:PassLen/binary, Rest/binary>>, State = #{socket := Socket}) ->
    Username = binary_to_list(UserBin),
    Password = binary_to_list(PassBin),
    NewState = case account_manager:authenticate(account_manager, Username, Password) of
        true ->
            send_auth_response(Socket, 1, "Login successful. Entering Matchmaker queue..."),
            matchmaker:join(matchmaker, Username, self()),
            State#{username => Username};
        false ->
            send_auth_response(Socket, 0, "Invalid username or password."),
            State
    end,
    handle_binary_payload(Rest, NewState);

handle_binary_payload(<<3:8, UserLen:16, UserBin:UserLen/binary, PassLen:16, PassBin:PassLen/binary, Rest/binary>>, State = #{socket := Socket}) ->
    Username = binary_to_list(UserBin),
    Password = binary_to_list(PassBin),
    case account_manager:cancel(account_manager, Username, Password) of
        ok -> send_auth_response(Socket, 1, "Account successfully deleted.");
        {error, _} -> send_auth_response(Socket, 0, "Failed to delete account.")
    end,
    handle_binary_payload(Rest, State);

handle_binary_payload(<<4:8, Left:8, Right:8, Forward:8, Rest/binary>>, State = #{game_room := GameRoomPid}) ->
    if GameRoomPid =/= undefined ->
           GameRoomPid ! {movement_input, self(), Left, Right, Forward};
       true -> ok
    end,
    handle_binary_payload(Rest, State);

handle_binary_payload(Unknown, State) ->
    io:format("Received unknown/fragmented payload: ~p~n", [Unknown]),
    State.

send_auth_response(Socket, Status, Message) ->
    MsgBin = list_to_binary(Message),
    MsgLen = byte_size(MsgBin),
    Packet = <<16:8, Status:8, MsgLen:16/integer, MsgBin/binary>>,
    gen_tcp:send(Socket, Packet).