-module(game_room).
-export([start/2, stop/1]).


start(MatchmakerPid, Players) ->
    Pid = spawn(fun() -> init(MatchmakerPid, Players) end),
    {ok, Pid}.

stop(Pid) ->
    Pid ! stop,
    ok.


init(MatchmakerPid, PlayersList) ->
    io:format("Game Room started with ~p players!~n", [length(PlayersList)]),
    MapWidth = 1280.0, MapHeight = 720.0,
    
    lists:foreach(fun({PlayerId, _Username, ClientPid}) -> 
        ClientPid ! {game_started, self(), PlayerId, MapWidth, MapHeight} 
    end, PlayersList),

    PlayerMap = setup_players(PlayersList, #{}),
    ObjectMap = generate_objects(50, 10), 

    State = #{players => PlayerMap, objects => ObjectMap},

    erlang:send_after(33, self(), tick),
    erlang:send_after(120000, self(), match_end),
    loop(MatchmakerPid, State).

loop(MatchmakerPid, State = #{players := Players, objects := Objects}) ->
    receive
        {movement_input, ClientPid, Left, Right, Forward} ->
            NewPlayers = update_player_inputs(Players, ClientPid, Left, Right, Forward),
            loop(MatchmakerPid, State#{players => NewPlayers});

        tick ->
            MovedPlayers = physics(Players),
            
            {PlayersAfterOrbs, FinalObjects} = check_object_collisions(MovedPlayers, Objects),
            
            FinalPlayers = check_player_collisions(PlayersAfterOrbs),
            
            UpdatedState = State#{players => FinalPlayers, objects => FinalObjects},
            broadcast_state(UpdatedState),
            
            erlang:send_after(33, self(), tick),
            loop(MatchmakerPid, UpdatedState);

        {player_left, ClientPid} ->
            NewPlayers = maps:remove(ClientPid, Players),
            loop(MatchmakerPid, State#{players => NewPlayers});

        match_end ->
            io:format("2 Minute Match Ended!~n"),
            
            PlayerList = maps:values(Players),
            SortedPlayers = lists:sort(fun(#{score := S1}, #{score := S2}) -> S1 >= S2 end, PlayerList),
            
            case SortedPlayers of
                [#{score := HighestScore, username := WinnerName} | Rest] ->
                    IsTie = case Rest of
                        [#{score := SecondHighest} | _] when SecondHighest == HighestScore -> true;
                        _ -> false
                    end,
                    
                    if 
                        IsTie ->
                            io:format("Match Tie! Ignoring for leaderboard.~n"),
                            broadcast_match_end(Players, "TIE", HighestScore);
                        true ->
                            io:format("Winner is ~s with ~p captures!~n", [WinnerName, HighestScore]),
                            score_manager:add_winner(WinnerName, HighestScore),
                            broadcast_match_end(Players, WinnerName, HighestScore)
                    end;
                [] -> ok
            end,

            matchmaker:match_ended(MatchmakerPid),
            maps:fold(fun(ClientPid, _, _Acc) -> ClientPid ! stop end, ok, Players),
            ok;

        stop -> ok;
        _Unknown -> loop(MatchmakerPid, State)
    end.

setup_players([], State) -> State;
setup_players([{PlayerId, Username, ClientPid} | Rest], State) ->
    {StartX, StartY} = case PlayerId of
        1 -> {100.0, 100.0};  
        2 -> {1180.0, 100.0};  
        3 -> {100.0, 620.0};  
        4 -> {1180.0, 620.0};  
        _ -> {500.0, 500.0}   
    end,

    PlayerData = #{
        id => PlayerId,
        username => Username,
        x => StartX, y => StartY, 
        vx => 0.0, vy => 0.0,     
        angle => 0.0, mass => 10.0, score => 0,
        inputs => #{left => 0, right => 0, forward => 0}
    },
    NewState = maps:put(ClientPid, PlayerData, State),
    setup_players(Rest, NewState).

generate_objects(NumFood, NumPoison) ->
    generate_objects(NumFood, NumPoison, 1, #{}).

generate_objects(0, 0, _Id, Acc) -> Acc;
generate_objects(FoodLeft, PoisonLeft, Id, Acc) ->
    X = 20.0 + rand:uniform() * 1240.0,
    Y = 20.0 + rand:uniform() * 680.0,

    RandomRadius = 3.0 + (rand:uniform() * 5.0),
    
    {NewFood, NewPoison, Type} = if 
        FoodLeft > 0 -> {FoodLeft - 1, PoisonLeft, 1}; 
        true ->         {0, PoisonLeft - 1, 2}         
    end,

    Obj = #{id => Id, x => X, y => Y, radius => RandomRadius, type => Type},
    generate_objects(NewFood, NewPoison, Id + 1, maps:put(Id, Obj, Acc)).

get_min_player_radius(Players) ->
    maps:fold(fun(_Pid, #{mass := M}, MinAcc) ->
        R = math:sqrt(M / math:pi()) * 10.0,
        if R < MinAcc -> R; true -> MinAcc end
    end, 100000.0, Players).

exists_smaller_food(Objects, MinR) ->
    maps:fold(fun(_Id, #{radius := R, type := Type}, Found) ->
        Found orelse (Type == 1 andalso R < MinR)
    end, false, Objects).

update_player_inputs(State, ClientPid, Left, Right, Forward) ->
    case maps:find(ClientPid, State) of
        {ok, PlayerData} ->
            NewInputs = #{left => Left, right => Right, forward => Forward},
            UpdatedPlayer = PlayerData#{inputs => NewInputs},
            maps:put(ClientPid, UpdatedPlayer, State);
        error ->
            State
    end.

physics(State) ->
    maps:map(fun(_ClientPid, PlayerData = #{x := X, y := Y, vx := Vx, vy := Vy, angle := Angle, mass := Mass, inputs := Inputs}) ->
        
       
        TurnSpeed = 1.5 / Mass, 
        NewAngle = case {maps:get(left, Inputs), maps:get(right, Inputs)} of
            {1, 0} -> Angle - TurnSpeed;
            {0, 1} -> Angle + TurnSpeed;
            _ -> Angle
        end,

        Thrust = case maps:get(forward, Inputs) of
            1 -> 15.0 / Mass; 
            0 -> 0.0
        end,

        NewVx = Vx + (math:cos(NewAngle) * Thrust),
        NewVy = Vy + (math:sin(NewAngle) * Thrust),

        FinalVx = NewVx * 0.95,
        FinalVy = NewVy * 0.95,

        CalculatedX = X + FinalVx,
        CalculatedY = Y + FinalVy,

        BoundedX = max(20.0, min(1260.0, CalculatedX)),
        BoundedY = max(20.0, min(700.0, CalculatedY)),

        WallVx = case BoundedX == CalculatedX of true -> FinalVx; false -> 0.0 end,
        WallVy = case BoundedY == CalculatedY of true -> FinalVy; false -> 0.0 end,

        PlayerData#{
            x => BoundedX, y => BoundedY,
            vx => WallVx, vy => WallVy,
            angle => NewAngle
        }
    end, State).

check_object_collisions(Players, Objects) ->
    maps:fold(fun(ClientPid, PlayerData, {AccPlayers, AccObjects}) ->
        {UpdatedPlayer, UpdatedObjects} = player_eat_objects(Players, PlayerData, AccObjects),
        
        {maps:put(ClientPid, UpdatedPlayer, AccPlayers), UpdatedObjects}
    end, {#{}, Objects}, Players).

player_eat_objects(Players, Player = #{x := Px, y := Py, mass := Mass}, Objects) ->
    PRadius = math:sqrt(Mass / math:pi()) * 10.0,
    
    maps:fold(fun(ObjId, Obj = #{x := Ox, y := Oy, radius := ORadius, type := Type}, {AccPlayer, AccObjs}) ->
        Dist = math:sqrt((Px - Ox)*(Px - Ox) + (Py - Oy)*(Py - Oy)),
        
        IsCollision = case Type of
            1 -> Dist + ORadius =< PRadius; 
            2 -> Dist =< PRadius + ORadius 
        end,
        
        case IsCollision of
            true ->
                CurrentMass = maps:get(mass, AccPlayer),                
                MassImpact = ORadius / 3.0, 
                
                NewMass = case Type of
                    1 -> CurrentMass + MassImpact;
                    2 -> max(5.0, CurrentMass - MassImpact)
                end,

                MinPlayerR = get_min_player_radius(Players),

                TempObjs = maps:remove(ObjId, AccObjs),
                SmallerExists = exists_smaller_food(TempObjs, MinPlayerR),
                
                NewObjRadius = if 
                    not SmallerExists -> 
                        MinPlayerR * 0.7; 
                    true -> 
                        3.0 + (rand:uniform() * 25.0) 
                end,
                
                ReplacementObj = Obj#{
                    x => 20.0 + rand:uniform() * 1240.0, 
                    y => 20.0 + rand:uniform() * 680.0,
                    radius => NewObjRadius
                },
                
                {AccPlayer#{mass => NewMass}, maps:put(ObjId, ReplacementObj, AccObjs)};
            false ->
                {AccPlayer, AccObjs}
        end
    end, {Player, Objects}, Objects).


check_player_collisions(Players) ->
    PlayerList = maps:to_list(Players),
    resolve_pvp(PlayerList, Players).

resolve_pvp([], Players) ->
    Players;
resolve_pvp([{ClientPid, _} | Rest], Players) ->
    case maps:find(ClientPid, Players) of
        {ok, PlayerData} ->
            UpdatedPlayers = try_eat_others(ClientPid, PlayerData, Rest, Players),
            resolve_pvp(Rest, UpdatedPlayers);
        error ->
            resolve_pvp(Rest, Players)
    end.

try_eat_others(_P1Pid, _P1Data, [], Players) ->
    Players;
try_eat_others(P1Pid, P1Data, [{P2Pid, _} | Rest], Players) ->
    case maps:find(P2Pid, Players) of
        {ok, P2Data} ->
            #{x := X1, y := Y1, mass := M1, score := S1} = P1Data,
            #{x := X2, y := Y2, mass := M2, score := S2} = P2Data,

            R1 = math:sqrt(M1 / math:pi()) * 10.0,
            R2 = math:sqrt(M2 / math:pi()) * 10.0,

            Dist = math:sqrt((X1 - X2)*(X1 - X2) + (Y1 - Y2)*(Y1 - Y2)),

            if
                (M1 > M2) andalso (Dist + R2 =< R1) ->
                    
                    NewP1 = P1Data#{mass => M1 + (M2 / 4.0), score => S1 + 1},
                    
                    NewP2 = P2Data#{
                        x => 20.0 + rand:uniform() * 1240.0,
                        y => 20.0 + rand:uniform() * 680.0,
                        mass => 10.0, score => S2
                    },
                    
                    NewPlayers = maps:put(P1Pid, NewP1, maps:put(P2Pid, NewP2, Players)),
                    try_eat_others(P1Pid, NewP1, Rest, NewPlayers);

                (M2 > M1) andalso (Dist + R1 =< R2) ->
                    NewP2 = P2Data#{mass => M2 + (M1 / 4.0), score => S2 + 1},
                    
                    NewP1 = P1Data#{
                        x => 20.0 + rand:uniform() * 1240.0,
                        y => 20.0 + rand:uniform() * 680.0,
                        mass => 10.0, score => S1
                    },
                    
                    NewPlayers = maps:put(P2Pid, NewP2, maps:put(P1Pid, NewP1, Players)),
                    NewPlayers;

                true ->
                    try_eat_others(P1Pid, P1Data, Rest, Players)
            end;
        error ->
            try_eat_others(P1Pid, P1Data, Rest, Players)
    end.

broadcast_state(State = #{players := Players}) ->
    Packet = build_state_packet(State),
    
    maps:fold(fun(ClientPid, _PlayerData, _Acc) ->
        ClientPid ! {send_raw_packet, Packet},
        ok
    end, ok, Players).

build_state_packet(#{players := Players, objects := Objects}) ->
    NumPlayers = maps:size(Players),
    PlayersBin = maps:fold(fun(_ClientPid, #{id := Id, x := X, y := Y, angle := Angle, mass := Mass, score := Score}, AccBin) ->

        PlayerBin = <<Id:32/integer, X:32/float, Y:32/float, Angle:32/float, Mass:32/float, Score:32/integer>>,
        <<AccBin/binary, PlayerBin/binary>>
    end, <<>>, Players),

    NumObjects = maps:size(Objects),
    ObjectsBin = maps:fold(fun(_ObjId, #{id := Id, x := X, y := Y, radius := R, type := Type}, AccBin) ->
        ObjBin = <<Id:32/integer, X:32/float, Y:32/float, R:32/float, Type:8/integer>>,
        <<AccBin/binary, ObjBin/binary>>
    end, <<>>, Objects),

    <<19:8, NumPlayers:8, PlayersBin/binary, NumObjects:16/integer, ObjectsBin/binary>>.

broadcast_match_end(Players, WinnerName, HighestScore) ->
    WinnerBin = list_to_binary(WinnerName),
    NameLen = byte_size(WinnerBin),
    
    Packet = <<20:8, NameLen:16/integer, WinnerBin/binary, HighestScore:32/integer>>,
    
    maps:fold(fun(ClientPid, _Data, _Acc) ->
        ClientPid ! {send_raw_packet, Packet},
        ok
    end, ok, Players).