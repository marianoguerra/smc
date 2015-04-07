-module(smc_triq).
-compile(export_all).

-include_lib("triq/include/triq.hrl").

smc_statem() ->
    ?FORALL(Cmds, triq_statem:commands(?MODULE),
            begin
                {_, State, ok} = triq_statem:run_commands(?MODULE, Cmds),
                #{ref := Ref} = State,
                stopped = smc:stop(Ref),
                true
            end).

initial_state() ->
    {ok, Ref} = smc:history([{get_seqnum, fun get_seqnum/1}]),
    #{ref => Ref, subscribed => false, num => 0}.

get_seqnum(Num) -> Num.

command(#{ref := Ref, subscribed := true, num := Num}) ->
    oneof([{call, smc, unsubscribe, [Ref, self()]},
           {call, smc, send, [Ref, Num]}]);
command(#{ref := Ref, subscribed := false, num := Num}) ->
    oneof([{call, smc, subscribe, [Ref, self()]},
           {call, smc, send, [Ref, Num]}]).

precondition(_State, _Call) ->
    true.

postcondition(#{subscribed := false}, {call, smc, send, [_Ref, _Num]}, _Result) ->
    receive
        _Val -> false
    after 1 ->
          true
    end;

postcondition(#{subscribed := true}, {call, smc, send, [_Ref, Num]}, _Result) ->
    receive
        Num -> true;
        _Other ->
            %io:format("got other ~p != ~p~n", [Num, Other]),
            false
    end;
postcondition(_State, _Call, _Result) ->
    true.

next_state(State=#{subscribed := true, num := Num}, _Var, {call, smc, send, [_Ref, _Val]}) ->
    State#{num => Num + 1};
next_state(State=#{subscribed := false, num := Num}, _Var, {call, smc, send, [_Ref, _Val]}) ->
    State#{num => Num + 1};
next_state(State, _Var, {call, smc, subscribe, [_Ref, _Pid]}) ->
    State#{subscribed => true};
next_state(State, _Var, {call, smc, unsubscribe, [_Ref, _Pid]}) ->
    State#{subscribed => false}.

