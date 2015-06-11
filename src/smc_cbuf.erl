-module(smc_cbuf).
-export([new/1, add/2, remove_percentage/2, size/1, size_bytes/1,
         takewhile_reverse/2]).

% a kind of circular buffer that is only useful for smc_channel to keep the
% last N events, it has a MinCount and a MaxCount to avoid calling sublist on
% every add call when the buffer is full, by default the buffer will grow to
% twice the MinCount before being cut to MinCount, the items are stored in
% reverse order to take advantage of cons and because it's the default access
% pattern (get the last N events).
% take into account that when the buffer has more than MinCount and you operate
% on it you may get more than MinCount items in response, we don't hide the
% elements after MinCount

-record(state, {min_count=50, max_count=100, current_count=0,
                max_size=1048576, current_size=0,
                % when size of items in buffer goes over max_size the buffer
                % will be reduced to contain size_percent_cut of max_size
                % for example, if max is 1MB and the buffer goes over then
                % the buffer will be reduced to approx 0.5MB
                size_percent_cut=0.5,
                items=[]}).

new(Opts) ->
    MinCount = proplists:get_value(min_count, Opts, 50),
    MaxCount = proplists:get_value(min_count, Opts, 100),
    MaxSizeBytes= proplists:get_value(max_size_bytes, Opts, 1048576),
    SizePercentCut = proplists:get_value(size_percent_cut, Opts, 0.5),
    #state{min_count=MinCount, max_count=MaxCount, max_size=MaxSizeBytes,
          size_percent_cut=SizePercentCut}.

add(State=#state{min_count=MinCount, max_count=MaxCount, current_count=Count,
                 items=Items}, Item) when Count >= MaxCount ->

    NewItems = lists:sublist(Items, MinCount),
    add(State#state{current_count=MinCount, items=NewItems}, Item);

add(State=#state{max_size=MaxSizeBytes, current_size=CurSize,
                 size_percent_cut=SizePercentCut, items=Items},
    Item) when CurSize >= MaxSizeBytes ->

    NewMaxSize = CurSize * SizePercentCut,

    % NOTE: this goes over all items, it doesn't stop when ready
    R = lists:foldl(fun ({ItSize, _ItVal}=It, {ToKeep, CSize, CurCount, Finished}) ->
                            NextSize = ItSize + CSize,
                            if Finished orelse NextSize > NewMaxSize ->
                                   {ToKeep, CSize, CurCount, true};
                               true ->
                                   {[It|ToKeep], NextSize, CurCount + 1, false}
                            end
                    end, {[], 0, 0, false}, Items),

    {NewItemsRev, NewSize, NewCount, _Finished} = R,
    NewItems = lists:reverse(NewItemsRev),
    NewState = State#state{current_count=NewCount, items=NewItems,
                           current_size=NewSize},
    add(NewState, Item);

add(State=#state{current_count=Count, current_size=Size, items=Items}, Item) ->
    SizeBytes = erlang:external_size(Item),
    State#state{current_count=Count + 1, current_size=Size + SizeBytes,
                items=[{SizeBytes, Item}|Items]}.

size(#state{current_count=Count}) -> Count.
size_bytes(#state{current_size=Size}) -> Size.

remove_percentage(State=#state{current_count=Count, min_count=MinCount, items=Items},
                  Percentage) ->
    NewItemCount = trunc(Count * Percentage),
    NewItems = lists:sublist(Items, MinCount),
    NewSize = lists:foldl(fun ({ItemSize, _It}, CurSize) ->
                                  CurSize + ItemSize
                          end, 0, NewItems),
    State#state{current_count=NewItemCount, current_size=NewSize, items=NewItems}.

takewhile_reverse(#state{items=Items}, Fun) ->
    R0 = lists:takewhile(fun ({_SizeBytes, Item}) -> Fun(Item) end, Items),
    lists:map(fun unwrap/1, R0).

% private

unwrap({_SizeBytes, Item}) -> Item.


