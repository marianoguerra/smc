-module(smc_channels_sup).

-behaviour(supervisor).

-export([init/1]).
-export([start_link/0, start_child/2]).

start_link() ->
    supervisor:start_link(?MODULE, []).

init(_) ->
    % TODO: think about this values
    MaxRestarts = 3,
    MaxSecondsBetweenRestarts = 5,
    Restart = temporary,
    Shutdown = 1000,
    Type = worker,
    SupFlags = {simple_one_for_one, MaxRestarts, MaxSecondsBetweenRestarts},
    ChildSpec = {smc_hist_channel,
            {smc_hist_channel, start_link, []},
            Restart, Shutdown, Type, [smc_hist_channel]},
    {ok, {SupFlags, [ChildSpec]}}.

start_child(SupRef, Opts) ->
    supervisor:start_child(SupRef, [Opts]).
