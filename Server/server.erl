-module(server).
-export([start/0]).

start() ->
    io:format("Starting Game Server...~n"),

    {ok, AccountPid} = account_manager:start(),
    {ok, _ScorePid}  = score_manager:start(),
    {ok, MatchmakerPid} = matchmaker:start(),
    {ok, _ListenerPid}  = tcp_listener:start(8080),

    register(account_manager, AccountPid),
    
    catch register(matchmaker, MatchmakerPid),

    io:format("All services started successfully!~n"),

    receive
        stop -> 
            io:format("Server shutting down.~n"),
            ok
    end.