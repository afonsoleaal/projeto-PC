-module(tcp_listener).
-export([start/1, accept_loop/1]).

start(Port) ->
    {ok, ListenSocket} = gen_tcp:listen(Port, [{active, false}, {packet, raw}, binary, {reuseaddr, true}, {nodelay, true}]),
    io:format("Server listening on port ~p~n", [Port]),
    
    Pid = spawn_link(?MODULE, accept_loop, [ListenSocket]),
    {ok, Pid}.

accept_loop(ListenSocket) ->
    {ok, ClientSocket} = gen_tcp:accept(ListenSocket),
    io:format("New client connected!~n"),
    
    {ok, _} = player_connection:start(ClientSocket),
    accept_loop(ListenSocket).