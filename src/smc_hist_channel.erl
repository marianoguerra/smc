-module(smc_hist_channel).
-behaviour(gen_server).

-export([start_link/1, subscribe/2, subscribe/3, unsubscribe/2, send/2,
         replay/3, stop/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-record(state, {buffer, channel, check_interval_ms=30000, sub_count=0,
                get_seqnum, name}).

%% API

start_link(Opts) ->
    gen_server:start_link(?MODULE, Opts, []).

replay(Channel, Pid, FromSeqNum) ->
    gen_server:call(Channel, {replay, Pid, FromSeqNum}).

subscribe(Channel, Pid) ->
    subscribe(Channel, Pid, nil).

% will replay including FromSeqNum (that is >= FromSeqNum)
subscribe(Channel, Pid, FromSeqNum) ->
    gen_server:call(Channel, {subscribe, Pid, FromSeqNum}).

unsubscribe(Channel, Pid) ->
    gen_server:call(Channel, {unsubscribe, Pid}).

send(Channel, Event) ->
    gen_server:call(Channel, {send, Event}).

stop(Channel) ->
    gen_server:call(Channel, stop).

%% Server implementation, a.k.a.: callbacks

init(Opts) ->
    BufferSize = proplists:get_value(buffer_size, Opts, 50),
    ChannelName = proplists:get_value(name, Opts, <<"anon-channel">>),
    {get_seqnum, GetSeqNum} = proplists:lookup(get_seqnum, Opts),
    Buffer = smc_cbuf:new(BufferSize),
    {ok, Channel} = smc_channel:start_link(),
    State = #state{channel=Channel, buffer=Buffer, get_seqnum=GetSeqNum,
                  name=ChannelName},
    {ok, State, State#state.check_interval_ms}.

handle_call({subscribe, Pid, nil}, _From,
            State=#state{channel=Channel, sub_count=SubCount}) ->
    smc_channel:subscribe(Channel, Pid),
    NewSubCount = SubCount + 1,
    NewState = State#state{sub_count=NewSubCount},
    {reply, ok, NewState, NewState#state.check_interval_ms};

handle_call({subscribe, Pid, FromSeqNum}, _From,
            State=#state{channel=Channel, buffer=Buffer, sub_count=SubCount,
                        get_seqnum=GetSeqNum}) ->
    do_replay(Pid, FromSeqNum, Buffer, GetSeqNum),
    smc_channel:subscribe(Channel, Pid),
    NewSubCount = SubCount + 1,
    NewState = State#state{sub_count=NewSubCount},
    {reply, ok, NewState, NewState#state.check_interval_ms};

handle_call({unsubscribe, Pid}, _From,
            State=#state{channel=Channel, sub_count=SubCount}) ->
    smc_channel:unsubscribe(Channel, Pid),
    NewSubCount = SubCount - 1,
    NewState = State#state{sub_count=NewSubCount},
    {reply, ok, NewState, NewState#state.check_interval_ms};

handle_call({send, Event}, _From, State=#state{channel=Channel, buffer=Buffer}) ->
    NewBuffer = smc_cbuf:add(Buffer, Event),
    NewState = State#state{buffer=NewBuffer},
    smc_channel:send(Channel, Event),
    {reply, ok, NewState, State#state.check_interval_ms};

handle_call({replay, Pid, FromSeqNum}, _From,
            State=#state{buffer=Buffer, get_seqnum=GetSeqNum}) ->
    do_replay(Pid, FromSeqNum, Buffer, GetSeqNum),
    {reply, ok, State, State#state.check_interval_ms};

handle_call(stop, _From, State) ->
    {stop, normal, stopped, State}.

handle_cast(Msg, State) ->
    io:format("Unexpected handle cast message: ~p~n", [Msg]),
    {noreply, State}.

handle_info(timeout, State=#state{buffer=Buffer, sub_count=SubCount}) ->
    NewBuffer = smc_cbuf:remove_percentage(Buffer, 0.5),
    NewBufferSize = smc_cbuf:size(NewBuffer),
    NewState = State#state{buffer=NewBuffer},

    if
        NewBufferSize == 0 andalso SubCount == 0 ->
            lager:debug("channel buffer empty and no subscribers, stopping channel"),
            {stop, normal, NewState};
        true ->
            lager:debug("reduced channel buffer because of inactivity to ~p items",
                      [NewBufferSize]),
            {noreply, NewState, State#state.check_interval_ms}
    end;

handle_info({gen_event_EXIT, Handler, Reason}, State=#state{sub_count=SubCount}) ->
    lager:info("handler removed due to exit ~p ~p", [Handler, Reason]),
    NewSubCount = SubCount - 1,
    NewState = State#state{sub_count=NewSubCount},
    {noreply, NewState};

handle_info(Msg, State) ->
    lager:warning("Unexpected handle info message: ~p~n", [Msg]),
    {noreply, State}.

terminate(_Reason, _Gblob) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

% private api

do_replay(Pid, FromSeqNum, Buffer, GetSeqNum) ->
    GtFromSeqNum = fun (Entry) ->
                           SeqNum = GetSeqNum(Entry),
                           SeqNum >= FromSeqNum
                   end,
    ToReplayReverse = smc_cbuf:takewhile_reverse(Buffer, GtFromSeqNum),
    ToReplay = lists:reverse(ToReplayReverse),
    Pid ! ToReplay,
    ok.
