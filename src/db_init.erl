-module(db_init).
-include("game.hrl").
%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------
-export([
         start/0
         ]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start() ->
    ?DEBUG("~p:init_db ~p", [?MODULE, ?LINE]),
    mnesia:create_schema([node()]),    
    mnesia:create_table(map,
                        [{ram_copies, [node()|nodes()]},   
                         {attributes, record_info(fields, map)}]),

    mnesia:create_table(city,   
                        [{ram_copies, [node()|nodes()]},   
                         {attributes, record_info(fields, city)}]),
    mnesia:add_table_index(city, author_id),
    mnesia:add_table_index(city, is_capital),

    mnesia:create_table(soldier,
                        [{ram_copies, [node()|nodes()]},   
                         {attributes, record_info(fields, soldier)}]),
    mnesia:add_table_index(soldier, city_id),
    mnesia:add_table_index(soldier, author_id),
    mnesia:add_table_index(soldier, author_id_state),
    ?DEBUG("~p:init_db ~p R=~p", [?MODULE, ?LINE, r1]),
    ok. 

