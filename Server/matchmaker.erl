-module(matchmaker).
-export([start/0, join/3, leave/1, match_ended/1, stop/1]).


start() ->
    Pid = spawn(fun() -> init() end),
    {ok, Pid}.


join(Pid, Username, ClientPid) ->
    Ref = make_ref(),
    Pid ! {{join, Username, ClientPid}, self(), Ref},
    receive
        {Ref, Reply} -> Reply
    after 5000 -> 
        {error, timeout}
    end.

leave(ClientPid) ->
    matchmaker ! {leave, ClientPid},
    ok.

match_ended(Pid) ->
    Pid ! match_ended,
    ok.

stop(Pid) ->
    Pid ! stop,
    ok.

init() ->
    erlang:send_after(2000, self(), broadcast_leaderboard),
    State = #{queue => [], active => 0, timer => undefined},
    loop(State).

loop(State) ->
    receive
        broadcast_leaderboard ->
            Queue = maps:get(queue, State),
            TopScores = score_manager:get_top(),
            broadcast_scores(Queue, TopScores),
            
            erlang:send_after(2000, self(), broadcast_leaderboard),
            loop(State);

        {{join, Username, ClientPid}, CallerPid, Ref} ->
            Queue = maps:get(queue, State),
            NewQueue = Queue ++ [{Username, ClientPid}], 
            CallerPid ! {Ref, ok},
            NewState = check_queue(State#{queue => NewQueue}),
            loop(NewState);

        {leave, ClientPid} ->
            Queue = maps:get(queue, State),
            NewQueue = lists:filter(fun({_U, Pid}) -> Pid =/= ClientPid end, Queue),
            NewState = State#{queue => NewQueue}, 
            io:format("Player left queue. ~p remaining.~n", [length(NewQueue)]),
            loop(NewState);    

        start_3_player_match ->
            StateNoTimer = State#{timer => undefined},
            NewState = try_start_match(StateNoTimer, 3),
            loop(NewState);


        match_ended ->
            Active = maps:get(active, State),
            DecrementedState = State#{active => max(0, Active - 1)},
            NewState = check_queue(DecrementedState),
            loop(NewState);

        stop ->
            ok;

        _Unknown ->
            loop(State)
    end.


check_queue(State = #{queue := Q, active := Active, timer := Timer}) ->
    if
        length(Q) >= 4 andalso Active < 4 ->
            cancel_timer(Timer), 
            {PlayersToStart, RemainingQ} = lists:split(4, Q),
            start_game_room(PlayersToStart),
            check_queue(State#{queue => RemainingQ, active => Active + 1, timer => undefined});

        length(Q) == 3 andalso Active < 4 andalso Timer == undefined ->
            NewTimer = erlang:send_after(10000, self(), start_3_player_match),
            State#{timer => NewTimer};

        length(Q) >= 3 andalso Active >= 4 ->
            cancel_timer(Timer),
            State#{timer => undefined};

        true ->
            State
    end.

try_start_match(State = #{queue := Q, active := Active}, NeededPlayers) ->
    if
        length(Q) >= NeededPlayers andalso Active < 4 ->
            {PlayersToStart, RemainingQ} = lists:split(NeededPlayers, Q),
            start_game_room(PlayersToStart),
            check_queue(State#{queue => RemainingQ, active => Active + 1});
        true ->
            State
    end.

cancel_timer(undefined) -> ok;
cancel_timer(Timer) -> erlang:cancel_timer(Timer).


start_game_room(Players) ->
    PlayersWithIds = assign_ids(1, Players),
    io:format(">>> SPANWING GAME ROOM WITH PLAYERS: ~p~n", [PlayersWithIds]),
    
    {ok, _RoomPid} = game_room:start(self(), PlayersWithIds),
    ok.

assign_ids(_Id, []) -> 
    [];
assign_ids(Id, [{Username, ClientPid} | Rest]) ->
    [{Id, Username, ClientPid} | assign_ids(Id + 1, Rest)].

broadcast_scores(WaitingPlayers, TopScores) ->
    NumEntries = length(TopScores),
    
    ScoresBin = lists:foldl(fun({Name, Score}, Acc) ->
        NameBin = list_to_binary(Name),
        NameLen = byte_size(NameBin),
        <<Acc/binary, NameLen:16/integer, NameBin/binary, Score:32/integer>>
    end, <<>>, TopScores),
    
    Packet = <<17:8, NumEntries:8, ScoresBin/binary>>,
    
    lists:foreach(fun({_Username, ClientPid}) ->
        ClientPid ! {send_raw_packet, Packet}
    end, WaitingPlayers).