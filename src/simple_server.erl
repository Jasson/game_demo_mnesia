-module(simple_server).
-behaviour(gen_server).
-define(SERVER, ?MODULE).
-include("game.hrl").
%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-export([create_city/2,
         get_city/2,
         change_tax/3,
         change_peoples/1,
         change_capital/2,
         collect_taxes/1,
         product_food/1,
         is_empty/2]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

-spec create_city({X::integer(), Y::integer()}, AuthorId::string()) -> 
        ok|{error, Reason::term()}.
create_city({X, Y}, AuthorId) ->
    ?DEBUG("~p:create_city ~p {X, Y}=~p, AuthorId=~p", [?MODULE, ?LINE, {X, Y}, AuthorId]),
    case is_empty({X, Y}, AuthorId) of
        "1" ->
            mnesia:dirty_write(#city{id={{X, Y}, AuthorId}, author_id=AuthorId}),
            mnesia:dirty_write(#map{id={{X,Y}, AuthorId}, is_empty="0"}),
            ok;
        "0" ->
            {error, "is exists"}
    end.

-spec is_empty({X::integer(), Y::integer()}, AuthorId::string()) ->  IsEmpty::string().
is_empty({X, Y}, AuthorId) ->
    case mnesia:dirty_read({map, {{X, Y}, AuthorId}}) of
        [] -> 
            ?DEBUG("~p:is_empty ~p IsEmpty=~p", [?MODULE, ?LINE, "1"]),
            "1";
        [#map{is_empty = IsEmpty}] -> 
            ?DEBUG("~p:is_empty ~p IsEmpty=~p", [?MODULE, ?LINE, IsEmpty]),
            IsEmpty
    end.

-spec get_city({X::integer(), Y::integer()}, AuthorId::string()) -> 
            city() |{error, Reason::string()}.
get_city({X, Y}, AuthorId) ->
    case is_empty({X, Y}, AuthorId) of
        "1" -> {error, "not exits"};
        "0" -> 
            [City] = mnesia:dirty_read({city, {{X, Y}, AuthorId}}),
            ?DEBUG("~p:get_city ~p City=~p", [?MODULE, ?LINE, City]),
            City
    end.

-spec change_tax({X::integer(), Y::integer()}, AuthorId::string(), Tax::float()) -> 
            ok|{error, Reason::string()}.
change_tax({X, Y}, AuthorId, Tax) ->
    case get_city({X, Y}, AuthorId) of
        {error, Error} ->
            ?ERROR("~p:change_tax ~p Error=~p", [?MODULE, ?LINE, Error]),
            {error, Error};
        City ->
            NewCity = City#city{gold_tax=Tax},
            ?DEBUG("~p:change_tax ~p NewCity=~p", [?MODULE, ?LINE, NewCity]),
            mnesia:dirty_write(NewCity),
            ok
    end.

-spec change_capital({X::integer(), Y::integer()}, AuthorId::string()) -> 
            ok|{error, Reason::string()}.
change_capital({X, Y}, AuthorId) ->
    case get_city({X, Y}, AuthorId) of
        {error, Error} ->
            ?ERROR("~p:change_capital ~p Error=~p ", [?MODULE, ?LINE, Error]);
        City ->
            case mnesia:dirty_index_read(city, "1", is_capital) of
                [] -> ok;
                [Capital] ->
                    mnesia:dirty_write(Capital#city{is_capital="0", product_food_rate=1000/60/60});
                R ->
                ?ERROR("~p:change_capital ~p Error=~p ", [?MODULE, ?LINE, R])
            end,
            NewCapital = City#city{is_capital="1", product_food_rate=10000/60/60},
            ?DEBUG("~p:change_capital ~p NewCapital=~p", [?MODULE, ?LINE, NewCapital]),
            mnesia:dirty_write(NewCapital)
    end.

-spec change_peoples(City::city()) -> city().
change_peoples(#city{id=CityId, peoples=Peoples, foods=Foods, gold_tax=Tax}=City) ->
    ?DEBUG("~p:change_peoples ~p ", [?MODULE, ?LINE]),
    Precent =
        if Peoples < Tax *1000 ->
              ?DEBUG("~p:change_peoples ~p <Peoples=~p", [?MODULE, ?LINE, Peoples]),
              0.05;
           Peoples > Tax *1000 ->
              ?DEBUG("~p:change_peoples ~p >Peoples=~p", [?MODULE, ?LINE, Peoples]),
              -0.05;
           true -> 
              ?DEBUG("~p:change_peoples ~p =Peoples=~p", [?MODULE, ?LINE, Peoples]),
              0
        end,
    NewPeoples = get_max_people(trunc(Precent*Peoples)) + Peoples,
    ?DEBUG("~p:change_peoples ~p NewPeoples=~p Precent=~p", 
           [?MODULE, ?LINE, NewPeoples, Precent]),
    food_crisis(Foods, CityId),
    mnesia:dirty_write(City#city{peoples=NewPeoples}).
           
    

collect_taxes(Time) ->
    ?DEBUG("~p:collect_taxes ~p Time=~p", [?MODULE, ?LINE, Time]),
    receive
    after Time ->
        collect_taxes(),
        collect_taxes(Time)
    end.
    
product_food(Time) ->
    ?DEBUG("~p:product_food ~p Time=~p", [?MODULE, ?LINE, Time]),
    receive 
    after Time ->
        product_food(),
        ?DEBUG("~p:product_food ~p Time=~p", [?MODULE, ?LINE, Time]),
        product_food(Time) 
    end.


    
%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) ->
    process_flag(trap_exit, true),
    Dict = dict:new(),
    gen_server:cast(?SERVER, {product_food}),
    gen_server:cast(?SERVER, {collect_taxes}),
    gen_server:cast(?SERVER, {consumer_food}),
    {ok, Dict}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.
handle_cast({consumer_food}, State) ->
    Pid = spawn_link(train_soldier, consumer_food, [?CONSUMER_FOOD_TIME]),
    NewState = dict:store(Pid, consumer_food, State),
    {noreply, NewState};
handle_cast({product_food}, State) ->
    Pid = spawn_link(?MODULE, product_food, [?PRODUCT_FOOD_TIME]),
    NewState = dict:store(Pid, product_food, State),
    {noreply, NewState};

handle_cast({collect_taxes}, State) ->
    Pid = spawn_link(?MODULE, collect_taxes, [?COLLECT_TAXES_TIME]),
    NewState = dict:store(Pid, collect_taxes, State),
    {noreply, NewState}.

handle_info({'EXIT', From, Reason}, State) ->
    ?DEBUG("~p:handel_info ~p Reason=~p", [?MODULE, ?LINE, Reason]),
    case dict:fetch(From, State) of
        product_food ->
            Pid = spawn_link(?MODULE, product_food, [?PRODUCT_FOOD_TIME]),
            NewState = dict:store(Pid, product_food, dict:erase(From, State));
        collect_taxes ->
            Pid = spawn_link(?MODULE, collect_taxes, [?COLLECT_TAXES_TIME]),
            NewState = dict:store(Pid, collect_taxes, dict:erase(From, State));
        consumer_food ->
            Pid = spawn_link(train_soldier, consumer_food, [?CONSUMER_FOOD_TIME/100]),
            NewState = dict:store(Pid, consumer_food, State)
            
    end,
    {noreply, NewState};

handle_info(_Info, State) ->
    ?DEBUG("~p:handel_info ~p Reason=~p", [?MODULE, ?LINE, _Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
-spec get_max_people(Num::integer()) ->integer().
get_max_people(Num) when Num < 1000 ->
    Num;
get_max_people(_Num) ->
    1000.

-spec get_golds(Golds::float(), Rate::float()) -> float().
get_golds(Golds, Rate) ->
    get_golds(Golds - Golds*Rate).

-spec get_golds(Golds::float()) -> float().
get_golds(Golds) when Golds < 0 ->
    0.0;
get_golds(Golds) ->
    Golds.



collect_taxes() ->
    Cities = ets:tab2list(city),
    Fun = fun(#city{golds=Golds,  gold_tax=Tax}=City) ->
              NewGolds = get_golds(Golds, Tax),
              change_peoples(City#city{golds=NewGolds})
          end,
    lists:foreach(Fun, Cities).

product_food() ->
    Cities = ets:tab2list(city),
    Fun = fun(#city{foods=Foods, product_food_rate=Rate}=City) ->
              mnesia:dirty_write(City#city{foods=Foods+Rate}) 
          end,
    lists:foreach(Fun, Cities).
    
-spec food_crisis(Foods::integer(), CityId::city_id()) -> ok.
food_crisis(Foods, _CityId) when Foods >0 ->
    ok;
food_crisis(_Foods, CityId) ->
    ?DEBUG("~p:food_crisis ~p CityId=~p", [?MODULE, ?LINE, CityId]),
    case mnesia:dirty_index_read(soldier, CityId, city_id) of
        [] -> ok;
        Soldiers when is_list(Soldiers) ->
            Fun  = fun(Soldier) ->
                       Sum=Soldier#soldier.sum,
                       NewSum=trunc(Sum*0.9), 
                       mnesia:dirty_write(Soldier#soldier{sum=NewSum})
                   end,
            lists:foreach(Fun, Soldiers),
            ok;
        _Other ->
            ok
    end.

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-ifdef(TEST).
change_peoples_test1() ->
    application:start(game),
    X2 = 2, Y2=2, AuthorId = "langxw",
    Y1=1,
    MatchCity21 =
        {city, {{2, 1}, "langxw"}, "cityname", "langxw", 
                0.0, 1000/60/60, 0.0, 0.1, 100, 0, "0"},
    create_city({X2, Y1}, AuthorId),
    change_tax({X2, Y1}, AuthorId, 0.1),
    City21 = get_city({X2, Y1}, AuthorId),
    change_peoples(City21),
    NewCity21 = get_city({X2, Y1}, AuthorId),

    ?DEBUG("~p:change_peoples_test ~p NewCity21=~p", [?MODULE, ?LINE, NewCity21]),
    ?DEBUG("~p:change_peoples_test ~p MatchCity21=~p", [?MODULE, ?LINE, MatchCity21]),

    MatchCity22 =
        {city, {{2, 2}, "langxw"}, "cityname", "langxw", 
                0.0, 1000/60/60, 0.0, 0.2, 197, 0, "0"},
    create_city({X2, Y2}, AuthorId),
    City22 = get_city({X2, Y2}, AuthorId),
    Fun = fun(_N, Acc) ->
                change_peoples(Acc),
                get_city({X2, Y2}, AuthorId)
          end,
    lists:foldl(Fun, City22, lists:seq(1,19)),
    NewCity22 = get_city({X2, Y2}, AuthorId),

    ?DEBUG("~p:change_peoples_test ~p MatchCity22=~p", [?MODULE, ?LINE, MatchCity22]),
    ?DEBUG("~p:change_peoples_test ~p NewCity22=~p", [?MODULE, ?LINE, NewCity22]),
    [
     ?assertMatch(MatchCity21, NewCity21),
     ?assertMatch(MatchCity22, NewCity22)
    ].


init_test1() ->
    application:start(game),
    [?assertMatch(ok, ok)
    ].
create_city_test1() ->
    application:start(game),
    X = 1, Y=1, AuthorId = "langxw",
    EmptyList = is_empty({X, Y}, AuthorId),
    Success = create_city({X, Y}, AuthorId),
    create_city({0, 0}, AuthorId),
    NotEmpty = is_empty({X, Y}, AuthorId),
    {Failure, _} = create_city({X, Y}, AuthorId),
    City = get_city({X, Y}, AuthorId),
    MatchCity = {city, {{1, 1}, "langxw"}, "cityname", "langxw", 0.0, 1000/60/60, 0.0, 0.2, 100, 0, "0"},
    MatchCityTax = {city, {{1, 1}, "langxw"}, "cityname", "langxw", 0.0, 1000/60/60, 0.0, 0.1, 100, 0, "0"},
    MatchCapital = {city, {{1, 1}, "langxw"}, "cityname", "langxw", 0.0, 10000/60/60, 0.0, 0.1, 100, 0, "1"},
    MatchCapitalTime = {city, {{1, 1}, "langxw"}, "cityname", "langxw", 10000/60/60*2, 10000/60/60, 0.0, 0.1, 100, 0, "1"},
    ChangeTax = change_tax({X, Y}, AuthorId, 0.1),
    {ChangeTaxError, _} = change_tax({X, 2}, AuthorId, 0.1),
    CityTax = get_city({X, Y}, AuthorId),
    change_capital({X, Y}, AuthorId),
    change_capital({X, Y}, AuthorId),
    Capital = get_city({X, Y}, AuthorId),
    receive after 2000 -> ok end,
    CapitalTime = get_city({X, Y}, AuthorId),
    ?DEBUG("~p MatchCapitalTime=~p", [?LINE, MatchCapitalTime]),
    ?DEBUG("~p CapitalTime=~p", [?LINE, CapitalTime]),
    %change_peoples_test1(), 
    [
     %?assertMatch(ok, Init),
     ?assertMatch("1", EmptyList),
     ?assertMatch(ok, Success),
     ?assertMatch("0", NotEmpty),
     %?assertMathc("1", EmptyList),
     ?assertMatch(error, Failure),
     ?assertMatch(MatchCity, City),
     ?assertMatch(ok, ChangeTax),
     ?assertMatch(error, ChangeTaxError),
     ?assertMatch(MatchCityTax, CityTax),
     ?assertMatch(MatchCapital, Capital),
     ?assertMatch(MatchCapitalTime, CapitalTime),
     ?assert(1==1)
    ].
collect_taxes_test1() ->
    application:start(game),
    X2 = 2, Y2=2, AuthorId = "langxw",
    X1 = 1, Y1=1, AuthorId = "langxw",
    create_city({X2, Y2}, AuthorId),
    create_city({X1, Y1}, AuthorId),
    City22 = get_city({X2, Y2}, AuthorId),
    change_peoples(City22#city{golds=100.0}),
    change_tax({X2, Y2}, AuthorId, 0.1),
    collect_taxes(),
    MatchCity22 =
        {city, {{2, 2}, "langxw"}, "cityname", "langxw", 
                1000/60/60*2, 1000/60/60, 90.0, 0.1, 187, 0, "0"},
    CityTax22 = get_city({X2, Y2}, AuthorId),
    [
     ?assertMatch(MatchCity22, CityTax22)
    ].
respawn_test() ->
    receive after 4000 -> ok end,
    [].

-endif.

