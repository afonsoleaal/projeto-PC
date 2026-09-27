-module(score_manager).
-export([start/0, add_winner/2, get_top/0, loop/1]).

start() ->
    Pid = spawn(?MODULE, loop, [[]]),
    register(?MODULE, Pid),
    io:format("Score Manager started!~n"),
    {ok, Pid}.

add_winner(Name, Score) ->
    ?MODULE ! {add, Name, Score}.

get_top() ->
    ?MODULE ! {get, self()},
    receive
        {top_scores, Scores} -> Scores
    after 1000 -> []
    end.

loop(Scores) ->
    receive
        {add, Name, Score} ->
            List = [{Name, Score} | Scores],
            Sorted = lists:sort(fun({_, S1}, {_, S2}) -> S1 >= S2 end, List),
            Top10 = lists:sublist(Sorted, 10),
            loop(Top10);
            
        {get, CallerPid} ->
            CallerPid ! {top_scores, Scores},
            loop(Scores)
    end.