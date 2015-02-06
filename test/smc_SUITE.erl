-module(smc_SUITE).
-compile(export_all).

all() ->
    [chann_send_receive, chann_send_receive_unsub_send,
     hchann_send_receive, hchann_send_receive_unsub_send,
     chann_stop_send, replay_empty_channel, replay_after_last_channel,
     replay_after_some_channel].

get_seqnum({SeqNum, _Data}) -> SeqNum.

get_msg() ->
    receive
        {gen_event_EXIT,{smc_channel,_},normal} -> get_msg();
        Msg1 -> Msg1
    after
        10 -> none
    end.

new_simple() -> smc:simple().

new_history(Test) ->
    Name = atom_to_list(Test),
    GetSeqNum = fun get_seqnum/1,
    HOpts = [{name, Name}, {get_seqnum, GetSeqNum}],
    smc:history(HOpts).

init_per_suite(Config) -> 
    Config.

init_per_testcase(Test, Config) ->
    {ok, HChann} = new_history(Test),
    {ok, Chann} = new_simple(),
    [{channel, Chann}, {hchannel, HChann}|Config].

chann(Config) -> proplists:get_value(channel, Config).
hchann(Config) -> proplists:get_value(hchannel, Config).
 
end_per_testcase(_Test, Config) ->
    Chann = chann(Config), 
    HChann = hchann(Config), 
    ok = smc:stop(Chann),
    ok = smc:stop(HChann).

send_receive(Chann) ->
    smc:subscribe(Chann, self()),
    smc:send(Chann, {42, "hi"}),
    {42, "hi"} = get_msg().

send_receive_unsub_send(Chann) ->
    smc:subscribe(Chann, self()),
    smc:send(Chann, {42, "hi"}),
    smc:unsubscribe(Chann, self()),
    smc:send(Chann, {43, "hi again"}),
    {42, "hi"} = get_msg(),
    none = get_msg().

chann_send_receive(Config) ->
    Chann = chann(Config), 
    send_receive(Chann).

chann_send_receive_unsub_send(Config) ->
    Chann = chann(Config), 
    send_receive_unsub_send(Chann).

hchann_send_receive(Config) ->
    Chann = hchann(Config), 
    send_receive(Chann).

hchann_send_receive_unsub_send(Config) ->
    Chann = hchann(Config), 
    send_receive_unsub_send(Chann).

stop_send(Chann) ->
    smc:stop(Chann),
    smc:send(Chann, {42, "hi"}),
    none = get_msg().

chann_stop_send(_) ->
    {ok, Chann} = new_simple(),
    stop_send(Chann).

hchann_stop_send(_) ->
    {ok, Chann} = new_history(hchann_stop_send),
    stop_send(Chann).

replay_empty_channel(Config) ->
    Chann = hchann(Config), 
    smc:replay(Chann, self(), 43),
    [] = get_msg().

replay_after_last_channel(Config) ->
    Chann = hchann(Config), 
    smc:send(Chann, {42, "hi"}),
    smc:replay(Chann, self(), 43),
    [] = get_msg().

replay_after_some_channel(Config) ->
    Chann = hchann(Config), 
    smc:send(Chann, {42, "hi"}),
    smc:send(Chann, {43, "hi 1"}),
    smc:send(Chann, {44, "hi 2"}),
    smc:replay(Chann, self(), 43),
    [{43, "hi 1"}, {44, "hi 2"}] = get_msg().
