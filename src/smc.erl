-module(smc).

-export([simple/0, history/1, subscribe/2, unsubscribe/2, send/2, replay/3, stop/1]).

%% API

simple() ->
    case smc_channel:start_link() of
        {ok, Pid} -> {ok, {simple, Pid}};
        Other -> Other
    end.

history(Opts) ->
    case smc_hist_channel:start_link(Opts) of
        {ok, Pid} -> {ok, {history, Pid}};
        Other -> Other
    end.

subscribe({simple, Channel}, Pid) ->
    smc_channel:subscribe(Channel, Pid);
subscribe({history, Channel}, Pid) ->
    smc_hist_channel:subscribe(Channel, Pid).

unsubscribe({simple, Channel}, Pid) ->
    smc_channel:unsubscribe(Channel, Pid);
unsubscribe({history, Channel}, Pid) ->
    smc_hist_channel:unsubscribe(Channel, Pid).

send({simple, Channel}, Event) ->
    smc_channel:send(Channel, Event);
send({history, Channel}, Event) ->
    smc_hist_channel:send(Channel, Event).

stop({simple, Channel}) ->
    smc_channel:stop(Channel);
stop({history, Channel}) ->
    smc_hist_channel:stop(Channel).

replay({history, Channel}, Pid, FromSeqNum) ->
    smc_hist_channel:replay(Channel, Pid, FromSeqNum).
