-module(account_manager).
-export([start/0, register/3, cancel/3, authenticate/3, stop/1]).

start() ->
    Pid = spawn(fun() -> init() end),
    {ok, Pid}.

register(Pid, Username, Password) ->
    call(Pid, {register, Username, Password}).

cancel(Pid, Username, Password) ->
    call(Pid, {cancel, Username, Password}).

authenticate(Pid, Username, Password) ->
    call(Pid, {authenticate, Username, Password}).

stop(Pid) ->
    Pid ! stop,
    ok.

call(Pid, Message) ->
    Ref = make_ref(),
    Pid ! {Message, self(), Ref},
    receive
        {Ref, Reply} -> Reply
    after 5000 ->
        {error, timeout}
    end.

init() ->
    loop(#{}).

loop(Accounts) ->
    receive
        {{register, Username, Password}, CallerPid, Ref} ->
            case maps:is_key(Username, Accounts) of
                true ->
                    CallerPid ! {Ref, {error, user_exists}},
                    loop(Accounts); 
                false ->
                    NewAccounts = maps:put(Username, Password, Accounts),
                    CallerPid ! {Ref, ok},
                    loop(NewAccounts) 
            end;

        {{cancel, Username, Password}, CallerPid, Ref} ->
            case maps:find(Username, Accounts) of
                {ok, Password} -> 
                    NewAccounts = maps:remove(Username, Accounts),
                    CallerPid ! {Ref, ok},
                    loop(NewAccounts);
                _ -> 
                    CallerPid ! {Ref, {error, invalid_credentials}},
                    loop(Accounts)
            end;

        {{authenticate, Username, Password}, CallerPid, Ref} ->
            case maps:find(Username, Accounts) of
                {ok, Password} ->
                    CallerPid ! {Ref, true};
                _ ->
                    CallerPid ! {Ref, false}
            end,
            loop(Accounts); 


        stop ->
            
            ok;


        _Unknown ->
            loop(Accounts)
    end.