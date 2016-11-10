-module(riak_ql_pfitting_aggregate).
-behaviour(riak_ql_pfitting).
-behaviour(gen_server).
-export([start_link/0]).
-export([init/1,
         terminate/2,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         code_change/3]).

-export([define_column_mappings/2,
         get_output_columns/1,
         process/3]).

-export([create/1,
         create_aggregate_column_mapping/3]).

-record(state, {
          column_mappings :: [riak_ql_pfitting:column_mapping()]
         }).

%% TODO: include SQL_NULL instead
-ifndef(SQL_NULL).
-define(SQL_NULL, []).
-endif.

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif. %%TEST

-spec create_aggregate_column_mapping(atom(),
                                      function(),
                                      binary()) -> riak_ql_pfitting:column_mapping().
create_aggregate_column_mapping(AggregateFunA, AggregateFun, ColumnIdentifier)
    when AggregateFun =:= undefined ->
    create_aggregate_column_mapping(AggregateFunA, aggregate_fun_atom_to_fun(AggregateFunA),
                                    ColumnIdentifier);
create_aggregate_column_mapping(AggregateFunA, AggregateFun, ColumnIdentifier) ->
    riak_ql_pfitting:create_column_mapping(ColumnIdentifier,
                                           column_as_aggregate(AggregateFunA, ColumnIdentifier),
                                           unresolved,
                                           AggregateFun).

-spec create([riak_ql_pfitting:column_mapping()]) -> {ok, pid()}.
create(ColumnMappings) ->
    Res = {ok, Pid} = start_link(),
    define_column_mappings(Pid, ColumnMappings),
    Res.

aggregate_fun_atom_to_fun(sum) ->
    fun agg_fun_sum/2;
aggregate_fun_atom_to_fun(count) ->
    fun agg_fun_count/2;
aggregate_fun_atom_to_fun(min) ->
    fun agg_fun_min/2;
aggregate_fun_atom_to_fun(max) ->
    fun agg_fun_max/2.

column_as_aggregate(sum, ColumnIdentifier) when is_binary(ColumnIdentifier) ->
    list_to_binary("SUM(" ++ binary_to_list(ColumnIdentifier) ++ ")");
column_as_aggregate(count, ColumnIdentifier) when is_binary(ColumnIdentifier) ->
    list_to_binary("COUNT(" ++ binary_to_list(ColumnIdentifier) ++ ")");
column_as_aggregate(min, ColumnIdentifier) when is_binary(ColumnIdentifier) ->
    list_to_binary("MIN(" ++ binary_to_list(ColumnIdentifier) ++ ")");
column_as_aggregate(max, ColumnIdentifier) when is_binary(ColumnIdentifier) ->
    list_to_binary("MAX(" ++ binary_to_list(ColumnIdentifier) ++ ")").

%% riak_ql_pfitting
define_column_mappings(Pid, ColumnMappings) ->
    gen_server:call(Pid, {define_column_mappings, ColumnMappings}).

get_output_columns(Pid) ->
    gen_server:call(Pid, {get_output_columns}).

process(Pid, Columns, Rows) ->
    gen_server:call(Pid, {process, Columns, Rows}).

%% gen_server
start_link() ->
    gen_server:start_link(?MODULE, [], []).

init(_Args) ->
    {ok, #state{}}.

terminate(normal, _State) ->
    ok.

handle_call({define_column_mappings, ColumnMappings}, _From, State) ->
    {reply, ok, State#state{column_mappings = ColumnMappings}};
handle_call({get_output_columns}, _From,
            State=#state{column_mappings = undefined}) ->
    {reply, {ok, []}, State};
handle_call({get_output_columns}, _From,
            State=#state{column_mappings = ColumnMappings}) ->
    OutputColumnNames =
        [ riak_ql_pfitting:get_column_mapping_display_text(ColumnMapping) ||
          ColumnMapping <- ColumnMappings ],
    {reply, {ok, OutputColumnNames}, State};
handle_call({process, Columns, Rows}, _From,
            State = #state{column_mappings = ColumnMappings }) ->
    Res = process_aggregate(Columns, Rows, ColumnMappings),
    ResStatus = riak_ql_pfitting:get_process_result_status(Res),
    {reply, {ResStatus, Res}, State};
handle_call(_Req, _From, State) ->
    {noreply, State}.

handle_cast(_Req, State) ->
    {noreply, State}.

handle_info(_Req, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

agg_fun_sum(?SQL_NULL, Acc) ->
    Acc;
agg_fun_sum(FValue, ?SQL_NULL) ->
    FValue;
agg_fun_sum(FValue, Acc) ->
    Acc + FValue.

agg_fun_count(?SQL_NULL, Acc) ->
    Acc;
agg_fun_count(_FValue, ?SQL_NULL) ->
    1;
agg_fun_count(_FValue, Acc) ->
    Acc + 1.

agg_fun_min(?SQL_NULL, Acc) ->
    Acc;
agg_fun_min(FValue, ?SQL_NULL) ->
    FValue;
agg_fun_min(FValue, Acc) when FValue < Acc ->
    FValue;
agg_fun_min(_FValue, Acc) ->
    Acc.

agg_fun_max(?SQL_NULL, Acc) ->
    Acc;
agg_fun_max(FValue, ?SQL_NULL) ->
    FValue;
agg_fun_max(FValue, Acc) when FValue > Acc ->
    FValue;
agg_fun_max(_FValue, Acc) ->
    Acc.

row_aggregate(_Row, _Columns, [], _ORow, _OColumns, Acc) ->
    Acc; %%<< do NOT reverse, this is a proplist
row_aggregate([RowV|_RowT], [Column|_ColumnT],
                          [{Column, ColumnMappingFun}|ColumnMappingT],
                          ORow, OColumns, Acc) ->
    CAccId = {Column, ColumnMappingFun},
    CAcc = proplists:get_value(CAccId, Acc, ?SQL_NULL),
    AValue = ColumnMappingFun(RowV, CAcc),
    Acc1 = lists:keystore(CAccId, 1, Acc, {CAccId, AValue}),
    row_aggregate(ORow, OColumns, ColumnMappingT, ORow, OColumns, Acc1);
row_aggregate([_RowV|RowT], [_Column|ColumnT], ColumnMappingIdentifiers,
              ORow, OColumns, Acc) ->
    row_aggregate(RowT, ColumnT, ColumnMappingIdentifiers, ORow, OColumns, Acc).

process_aggregate(Columns, Rows, ColumnMappings) ->
    AggregateColumns = [ riak_ql_pfitting:get_column_mapping_display_text(ColumnMapping) ||
                     ColumnMapping <- ColumnMappings ],
    ColumnMappings1 = [ {riak_ql_pfitting:get_column_mapping_input_identifier(ColumnMapping),
                        riak_ql_pfitting:get_column_mapping_fun(ColumnMapping)}||
                                 ColumnMapping <- ColumnMappings],
    { AggregateValues, ProcessErrors} =
    try lists:foldl(fun (Row, Acc) ->
                            row_aggregate(Row, Columns, ColumnMappings1, Row, Columns, Acc)
                    end, [], Rows) of
        V -> {V, []}
    catch
        error:Error -> {[], [Error]}
    end,
    AggregateRows = case length(ProcessErrors) of
                        0 -> [[V || {_K, V} <- AggregateValues]];
                        _ -> []
                    end,
    riak_ql_pfitting:create_process_result(AggregateColumns,
                                           AggregateRows, ProcessErrors).

-ifdef(TEST).
map_simple_aggregate_column_mappings(SimpleColumnMappings) ->
    [create_aggregate_column_mapping(AggregateFunA, undefined, ColumnIdentifier) ||
     {AggregateFunA, ColumnIdentifier} <- SimpleColumnMappings].

process_setup(SimpleColumnMappings) ->
    ColumnMappings = map_simple_aggregate_column_mappings(SimpleColumnMappings),
    {ok, Pid} = ?MODULE:create(ColumnMappings),
    Columns = [<<"r">>, <<"i">>, <<"a">>, <<"k">>],
    Rows = [[1, <<"one">>, 1000, 1.0],
            [[],[],[],[]],
            [[], <<"two">>, 2000, 2.0],
            [3, [], 3000, 3.0],
            [4, <<"four">>, [], 4.0],
            [5, <<"five">>, 5000, []]],
    {Pid, Columns, Rows}.

expected_row(FieldExtractorFun, AggregateFun, InitialAcc, Rows) ->
    [ lists:foldl(fun (Row, Acc) ->
                           FValue = FieldExtractorFun(Row),
                           AggregateFun(FValue, Acc)
                   end, InitialAcc, Rows) ].

process_sum_third_field_test() ->
    AggregateColumn = <<"a">>,
    AggregateFunA = sum,
    AggregateFun = aggregate_fun_atom_to_fun(AggregateFunA),
    ExpectedColumns = [ column_as_aggregate(AggregateFunA, AggregateColumn) ],
    {Pid, Columns, Rows } = process_setup([{AggregateFunA, AggregateColumn}]),
    ExpectedRows = [expected_row(fun ([_F1, _F2, F3, _F4]) -> F3 end, AggregateFun, ?SQL_NULL, Rows)],
    ExpectedErrors = [],
    Processed = ?MODULE:process(Pid, Columns, Rows),
    ?assertEqual({ok, riak_ql_pfitting:create_process_result(ExpectedColumns,
                                                             ExpectedRows,
                                                             ExpectedErrors)},
                 Processed).

process_max_last_field_test() ->
    AggregateColumn = <<"k">>,
    AggregateFunA = max,
    AggregateFun = aggregate_fun_atom_to_fun(AggregateFunA),
    ExpectedColumns = [ column_as_aggregate(AggregateFunA, AggregateColumn) ],
    {Pid, Columns, Rows } = process_setup([{AggregateFunA, AggregateColumn}]),
    ExpectedRows = [expected_row(fun ([_F1, _F2, _F3, F4]) -> F4 end, AggregateFun, ?SQL_NULL, Rows)],
    ExpectedErrors = [],
    Processed = ?MODULE:process(Pid, Columns, Rows),
    ?assertEqual({ok, riak_ql_pfitting:create_process_result(ExpectedColumns,
                                                             ExpectedRows,
                                                             ExpectedErrors)},
                 Processed).

process_min_second_field_test() ->
    AggregateColumn = <<"i">>,
    AggregateFunA = min,
    AggregateFun = aggregate_fun_atom_to_fun(AggregateFunA),
    ExpectedColumns = [ column_as_aggregate(AggregateFunA, AggregateColumn) ],
    {Pid, Columns, Rows } = process_setup([{AggregateFunA, AggregateColumn}]),
    ExpectedRows = [expected_row(fun ([_F1, F2, _F3, _F4]) -> F2 end, AggregateFun, ?SQL_NULL, Rows)],
    ExpectedErrors = [],
    Processed = ?MODULE:process(Pid, Columns, Rows),
    ?assertEqual({ok, riak_ql_pfitting:create_process_result(ExpectedColumns,
                                                             ExpectedRows,
                                                             ExpectedErrors)},
                 Processed).

process_sum_first_field_test() ->
    AggregateColumn = <<"r">>,
    AggregateFunA = sum,
    AggregateFun = aggregate_fun_atom_to_fun(AggregateFunA),
    ExpectedColumns = [ column_as_aggregate(AggregateFunA, AggregateColumn) ],
    {Pid, Columns, Rows } = process_setup([{AggregateFunA, AggregateColumn}]),
    ExpectedRows = [expected_row(fun ([F1, _F2, _F3, _F4]) -> F1 end, AggregateFun, ?SQL_NULL, Rows)],
    ExpectedErrors = [],
    Processed = ?MODULE:process(Pid, Columns, Rows),
    ?assertEqual({ok, riak_ql_pfitting:create_process_result(ExpectedColumns,
                                                             ExpectedRows,
                                                             ExpectedErrors)},
                 Processed).

process_count_first_field_test() ->
    AggregateColumn = <<"r">>,
    AggregateFunA = count,
    AggregateFun = aggregate_fun_atom_to_fun(AggregateFunA),
    ExpectedColumns = [ column_as_aggregate(AggregateFunA, AggregateColumn) ],
    {Pid, Columns, Rows } = process_setup([{AggregateFunA, AggregateColumn}]),
    ExpectedRows = [expected_row(fun ([F1, _F2, _F3, _F4]) -> F1 end, AggregateFun, ?SQL_NULL, Rows)],
    ExpectedErrors = [],
    Processed = ?MODULE:process(Pid, Columns, Rows),
    ?assertEqual({ok, riak_ql_pfitting:create_process_result(ExpectedColumns,
                                                             ExpectedRows,
                                                             ExpectedErrors)},
                 Processed).

process_sum_varchar_field_test() ->
    AggregateColumn = <<"i">>,
    AggregateFunA = sum,
    ExpectedColumns = [ column_as_aggregate(AggregateFunA, AggregateColumn) ],
    {Pid, Columns, Rows } = process_setup([{AggregateFunA, AggregateColumn}]),
    ExpectedRows = [],
    ExpectedErrors = [badarith],
    Processed = ?MODULE:process(Pid, Columns, Rows),
    ?assertEqual({error, riak_ql_pfitting:create_process_result(ExpectedColumns,
                                                                ExpectedRows,
                                                                ExpectedErrors)},
                 Processed).

process_aggregate_all_fields_test() ->
    ColumnMappings = [{min, <<"i">>},
                      {sum, <<"a">>},
                      {max, <<"r">>},
                      {sum, <<"k">>}],
    NullRow = [ ?SQL_NULL || _I <- lists:seq(1, 4) ],
    AggregateFun = fun([F1, F2, F3, F4], [A1, A2, A3, A4]) ->
                           [agg_fun_max(F1, A1),
                            agg_fun_min(F2, A2),
                            agg_fun_sum(F3, A3),
                            agg_fun_sum(F4, A4)]
                   end,
    ExpectedColumns = [ column_as_aggregate(AggregateFunA, AggregateColumn) ||
                        {AggregateFunA, AggregateColumn} <- ColumnMappings],
    {Pid, Columns, Rows } = process_setup(ColumnMappings),
    ExpectedRow = expected_row(fun (Row) -> Row end, AggregateFun, NullRow, Rows),
    ExpectedRows = [[F2,F3,F1,F4] || [F1,F2,F3,F4] <- ExpectedRow],
    ExpectedErrors = [],
    Processed = ?MODULE:process(Pid, Columns, Rows),
    ?assertEqual({ok, riak_ql_pfitting:create_process_result(ExpectedColumns,
                                                             ExpectedRows,
                                                             ExpectedErrors)},
                 Processed).

process_aggregate_mean_preparation_test() ->
    %% this test stresses the accumulator's need to identify an aggregate,
    %% including the aggregate function, not just the identifier.
    %% and this test builds towards a key goal of the Riak Query Pipeline, to
    %% support AVERAGE (mean) by gathering the vnode-local aggregates in a
    %% manner that can be gathered and further processed, summing the sums and
    %% counts and dividing the resultant sums by counts at the coordinator who
    %% initiated the scatter-gather. Otherwise said, a lazy AVERAGE that in
    %% transit commutes.
    ColumnMappings = [{sum, <<"a">>},
                      {count, <<"a">>},
                      {sum, <<"k">>},
                      {count, <<"k">>}],
    NullRow = [ ?SQL_NULL || _I <- lists:seq(1, 4) ],
    SumFun = fun([_F1, _F2, F3, F4], [A1, A2, A3, A4]) ->
                     [A1,
                      A2,
                      agg_fun_sum(F3, A3),
                      agg_fun_sum(F4, A4)]
             end,
    CountFun = fun([_F1, _F2, F3, F4], [A1, A2, A3, A4]) ->
                     [A1,
                      A2,
                      agg_fun_count(F3, A3),
                      agg_fun_count(F4, A4)]
             end,
    ExpectedColumns = [ column_as_aggregate(AggregateFunA, AggregateColumn) ||
                        {AggregateFunA, AggregateColumn} <- ColumnMappings],
    {Pid, Columns, Rows } = process_setup(ColumnMappings),
    [[_A1, _A2, ASum3, ASum4]] = expected_row(fun (Row) -> Row end, SumFun, NullRow, Rows),
    [[_A1, _A2, ACount3, ACount4]] = expected_row(fun (Row) -> Row end, CountFun, NullRow, Rows),
    ExpectedRows = [[ASum3, ACount3, ASum4, ACount4]],
    ExpectedErrors = [],
    Processed = ?MODULE:process(Pid, Columns, Rows),
    ?assertEqual({ok, riak_ql_pfitting:create_process_result(ExpectedColumns,
                                                             ExpectedRows,
                                                             ExpectedErrors)},
                 Processed).

-endif. %%TEST
