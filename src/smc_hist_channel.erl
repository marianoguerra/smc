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

handle_call({subscribe, Pid, nil}, _From, State) ->
    NewState = do_subscribe(State, Pid),
    {reply, ok, NewState, NewState#state.check_interval_ms};

handle_call({subscribe, Pid, FromSeqNum}, _From,
            State=#state{buffer=Buffer, get_seqnum=GetSeqNum}) ->
    do_replay(Pid, FromSeqNum, Buffer, GetSeqNum),
    NewState = do_subscribe(State, Pid),
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
    lager:warning("Unexpected handle cast message: ~p~n", [Msg]),
    {noreply, State}.

handle_info(timeout, State=#state{buffer=Buffer, sub_count=SubCount, channel=Channel}) ->
    NewBuffer = smc_cbuf:remove_percentage(Buffer, 0.5),
    NewBufferSize = smc_cbuf:size(NewBuffer),
    NewState = State#state{buffer=NewBuffer},

    if
        NewBufferSize == 0 andalso SubCount =< 0 ->
            GEHandlers = gen_event:which_handlers(Channel),
            GEHandlersCount = length(GEHandlers),

            if GEHandlersCount /= SubCount ->
                   lager:warning("subcount mismatch ~p != ~p", [SubCount, GEHandlersCount]),
                   % since they don't match trust the gen_event handlers count
                   FixedState = NewState#state{sub_count=GEHandlersCount},

                   {noreply, FixedState, State#state.check_interval_ms};
               true ->
                   lager:debug("channel buffer empty and no subscribers, stopping channel"),
                   smc_channel:send(Channel, {smc, {closing,
                                                    [{buffer, NewBufferSize},
                                                     {subs, SubCount}]}}),

                   {stop, normal, NewState}
            end;

        true ->
            lager:debug("reduced channel buffer because of inactivity to ~p items",
                      [NewBufferSize]),
            smc_channel:send(Channel, {smc, {heartbeat,
                                             [{buffer, NewBufferSize},
                                              {subs, SubCount}]}}),
            {noreply, NewState, State#state.check_interval_ms}
    end;

handle_info({gen_event_EXIT, Handler, Reason}, State=#state{channel=Channel}) ->
    lager:debug("handler removed due to exit ~p ~p", [Handler, Reason]),
    % since we don't know for sure if this process unsubscribed itself we
    % ask gen_event how many subscribers we have
    NewSubCount = length(gen_event:which_handlers(Channel)),
    NewState = State#state{sub_count=NewSubCount},

    {noreply, NewState};

handle_info(Msg, State) ->
    lager:warning("Unexpected handle info message: ~p~n", [Msg]),
    {noreply, State}.

terminate(Reason, #state{channel=Channel}) ->
    smc_channel:send(Channel, {smc, {terminate, [{reason, Reason}]}}),
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

do_subscribe(State=#state{channel=Channel, sub_count=SubCount}, Pid) ->
    smc_channel:subscribe(Channel, Pid),
    NewSubCount = SubCount + 1,
    State#state{sub_count=NewSubCount}.

