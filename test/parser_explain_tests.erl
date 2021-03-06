%% -------------------------------------------------------------------
%%
%% EXPLAIN command tests for the Parser
%%
%%
%% Copyright (c) 2016 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(parser_explain_tests).

-include_lib("eunit/include/eunit.hrl").
-include("parser_test_utils.hrl").

explain_sql_test() ->
    ?sql_comp_assert_match(
       "explain select * from argle", explain,
       [{fields, [
                  {identifier, [<<"*">>]}
                 ]},
        {tables, <<"argle">>},
        {where, []}
       ]).

explain_sql_with_semicolon_test() ->
    ?sql_comp_assert_match(
       "explain select * from argle;", explain,
       [{fields, [
                  {identifier, [<<"*">>]}
                 ]},
        {tables, <<"argle">>},
        {where, []}
       ]).

explain_sql_with_semicolons_in_quotes_test() ->
    ?sql_comp_assert_match(
       "explain select * from \"table;name\" where ';' = asdf;", explain,
       [{fields, [
                  {identifier, [<<"*">>]}
                 ]},
        {tables, <<"table;name">>},
        {where, [{'=', <<"asdf">>, {binary, <<";">>}}]}
       ]).

explain_sql_semicolon_second_statement_test() ->
    ?sql_comp_fail("explain select * from asdf; select * from asdf").

explain_sql_multiple_semicolon_test() ->
    ?sql_comp_fail("explain select * from asdf;;").

select_quoted_sql_test() ->
    ?sql_comp_assert_match(
       "explain select * from \"argle\"", explain,
       [{fields, [
                  {identifier, [<<"*">>]}
                 ]},
        {tables, <<"argle">>},
        {where, []}
       ]).

select_quoted_keyword_sql_test() ->
    ?sql_comp_assert_match(
       "explain select * from \"select\"", explain,
       [{fields, [
                  {identifier, [<<"*">>]}
                 ]},
        {tables, <<"select">>},
        {where, []}
       ]).

select_nested_quotes_sql_test() ->
    ?sql_comp_assert_match(
       "explain select * from \"some \"\"quotes\"\" in me\"", explain,
       [{fields, [
                  {identifier, [<<"*">>]}
                 ]},
        {tables, <<"some \"quotes\" in me">>},
        {where, []}
       ]).

select_from_lists_sql_test() ->
    ?sql_comp_fail("explain select * from events, errors").

select_from_lists_with_where_sql_test() ->
    ?sql_comp_fail("explain select foo from events, errors where x = y").

select_fields_from_lists_sql_test() ->
    ?sql_comp_assert_match(
       "explain select hip, hop, dont, stop from events", explain,
       [{fields, [
                  {identifier, [<<"hip">>]},
                  {identifier, [<<"hop">>]},
                  {identifier, [<<"dont">>]},
                  {identifier, [<<"stop">>]}
                 ]},
        {tables, <<"events">>},
        {where, []}
       ]).

select_quoted_spaces_sql_test() ->
    ?sql_comp_assert_match(
       "explain select * from \"table with spaces\"", explain,
       [{fields, [
                  {identifier, [<<"*">>]}
                 ]},
        {tables, <<"table with spaces">>},
        {where, []}
       ]).

select_quoted_escape_sql_test() ->
    ?sql_comp_assert_match(
       "explain select * from \"table with spaces\" where "
       "\"co\"\"or\" = 'klingon''name' or "
       "\"co\"\"or\" = '\"'", explain,
       [{fields, [
                  {identifier, [<<"*">>]}
                 ]},
        {tables, <<"table with spaces">>},
        {where, [
                 {or_,
                  {'=', <<"co\"or">>, {binary, <<"\"">>}},
                  {'=', <<"co\"or">>, {binary, <<"klingon'name">>}}
                 }
                ]}
       ]).
