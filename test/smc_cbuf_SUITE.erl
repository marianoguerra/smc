-module(smc_cbuf_SUITE).
-compile(export_all).

all() -> [add_10_read_10, test_max_size, test_max_size_steps].

new_cbuf(_Test) ->
    smc_cbuf:new([]).

init_per_suite(Config) ->
    Config.

init_per_testcase(Test, Config) ->
    Buf = new_cbuf(Test),
    [{cbuf, Buf}|Config].

buf(Config) -> proplists:get_value(cbuf, Config).

end_per_testcase(_Test, _Config) ->
    ok.

add(Buf, Num) ->
    lists:foldl(fun (I, BufIn) ->
                        smc_cbuf:add(BufIn, I)
                end, Buf, lists:seq(1, Num)).

add_10_read_10(Config) ->
    Buf = buf(Config),
    NewBuf = add(Buf, 10),
    [10, 9, 8, 7, 6, 5, 4, 3, 2, 1] = smc_cbuf:takewhile_reverse(NewBuf, fun (_) -> true end).

check_max_size(MaxSize, Num, Result, ResultSize, ResultCount) ->
    Buf = smc_cbuf:new([{max_size_bytes, MaxSize}]),
    NewBuf = add(Buf, Num),
    Result = smc_cbuf:takewhile_reverse(NewBuf, fun (_) -> true end),
    ResultSize = smc_cbuf:size_bytes(NewBuf),
    ResultCount = smc_cbuf:size(NewBuf),
    NewBuf.

test_max_size(_Config) ->
    Buf = smc_cbuf:new([{max_size_bytes, 12}]),
    NewBuf = add(Buf, 10),
    % 1, 2, 3, 4
    % reduce by half and add 5
    % 3, 4, 5, 6
    % reduce by half and add 7
    % 5, 6, 7, 8
    % reduce by half and add 9
    % 7, 8, 9, 10
    [10, 9, 8, 7] = smc_cbuf:takewhile_reverse(NewBuf, fun (_) -> true end).

test_max_size_steps(_Config) ->
    check_max_size(12, 4, [4, 3, 2, 1], 12, 4),
    check_max_size(12, 5, [5, 4, 3], 9, 3),
    check_max_size(12, 6, [6, 5, 4, 3], 12, 4),
    check_max_size(12, 7, [7, 6, 5], 9, 3),
    check_max_size(12, 8, [8, 7, 6, 5], 12, 4),
    check_max_size(12, 9, [9, 8, 7], 9, 3),
    check_max_size(12, 10, [10, 9, 8, 7], 12, 4).
