-module(train_soldier).
-behaviour(gen_server).
-define(SERVER, ?MODULE).
-include("game.hrl").
%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0]).

-define(SPEND_TIME,1).
%-define(SPEND_TIME,1000).
%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-export([
         add_train/4,
         cancel_train/3,
         train/3,
         add_golds/2,
         get_soldier_for_city/1,
         consumer_food/1,
         is_empty/3,
         complete/3
         ]).

-record(state, {pids = dict:new(), 
                cities_id = dict:new(), 
                trains_id = dict:new(),
                max=5}).
%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

-spec add_train(Type::string(), CityId::city_id(), TrainId::string(),
                Numbers::integer()) -> ok.
add_train(Type, CityId, TrainId, Numbers) ->
    ?DEBUG("~p:add_train ~p Type=~p, CityId=~p", [?MODULE, ?LINE, Type,CityId]),
    gen_server:call(?SERVER, {add_train, Type, CityId, TrainId, Numbers}).

-spec cancel_train(Type::string(), CityId::city_id(), TrainId::string()) -> ok.
cancel_train(Type, CityId, TrainId) ->
    gen_server:call(?SERVER, {cancel_train, Type, CityId, TrainId}).
    
 

-spec consumer_food(Time::integer()) -> ok.
consumer_food(Time) ->
    receive 
    after Time ->
        consumer_food(),
        consumer_food(Time)
    end.
    

-spec train(Type::string(), CityId::city_id(), Time::integer()) -> ok.
train(Type, CityId, Time) ->
    ?DEBUG("~p:train ~p Time=~p", [?MODULE, ?LINE, Time]),
    receive 
        cancel_train ->
            ok
    after Time ->
        ?DEBUG("~p:train ~p Time=~p", [?MODULE, ?LINE, Time]),
        complete(self(), Type, CityId),
        ok
        %train(Time, CityId, Time) 
    end.

-spec add_golds(CityId::city_id(), Golds::integer()) -> 
            ok|{error, Reason::term()}.
add_golds(CityId, Golds) ->
    case mnesia:dirty_read(city, CityId) of
        [] -> {error, "the city not exists"};
        [City] ->
            mnesia:dirty_write(City#city{golds=Golds});
        Error ->
            ?DEBUG("~p:add_golds ~p Error=~p", [?MODULE, ?LINE, Error])
    end.

-spec get_soldier_for_city(CityId::city_id()) -> [soldier()].
get_soldier_for_city(CityId) ->
    Soldiers = mnesia:dirty_index_read(soldier, CityId, city_id),
    CurrentTime = calendar:datetime_to_gregorian_seconds(calendar:local_time()),
    Fun = fun(#soldier{state=2, time=Time}=Soldier)->
                 RemainSecond = 
                     CurrentTime - calendar:datetime_to_gregorian_seconds(Time),
                 Soldier#soldier{time=RemainSecond};
             (Soldier)->
                 Soldier#soldier{time=0}
                
          end,
    Result = lists:map(Fun, Soldiers),
    ?DEBUG("~p:get_soldier_for_city ~p Result=~p", [?MODULE, ?LINE, Result]),
    Result.


    
%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) ->
    process_flag(trap_exit, true),
    {ok, #state{}}.

handle_call({cancel_train, Type, CityId, TrainId}, _From, 
        #state{pids=Pids, cities_id=CitiesId,
               trains_id=TrainsId}=State) ->
    ?DEBUG("~p:handle_call ~p cancel_train TrainId=~p, TrainsId=~p",
        [?MODULE, ?LINE, TrainId, dict:to_list(TrainsId)]),
    R=dict:is_key(TrainId, TrainsId),
    ?DEBUG("~p:handle_call ~p cancel_train R=~p", [?MODULE, ?LINE, R]),
    case dict:is_key(TrainId, TrainsId) of
        false ->
            ?DEBUG("~p:handle_call ~p cancel_train", [?MODULE, ?LINE]),
            NewState = State;
        true ->
            ?DEBUG("~p:handle_call ~p cancel_train", [?MODULE, ?LINE]),
            NewCitiesId = dict:update_counter(CityId, -1, CitiesId),
            {Pid} = dict:fetch(TrainId, TrainsId),
            {train, Type, CityId, TrainId, Numbers} = dict:fetch(Pid, Pids),
            Pid ! cancel_train,
            NewPids = dict:erase(Pid, Pids),
            NewTrainsId = dict:erase(TrainId, TrainsId),
            [City] = mnesia:dirty_read(city, CityId),
            mnesia:dirty_write(City#city{peoples=Numbers+City#city.peoples}),
            NewState = State#state{pids = NewPids,
                                   trains_id = NewTrainsId,
                                   cities_id = NewCitiesId}
    end,
    ?DEBUG("~p:handle_call ~p cancel_train", [?MODULE, ?LINE]),
    {reply, ok, NewState};
handle_call({add_train, Type, CityId, TrainId, Numbers}, _From, 
            #state{pids=Pids, trains_id=TrainsId,
            max=Max, cities_id=CitiesId}=State) ->

    ?DEBUG("~p:handle_call ~p add_train TrainId=~p, State=~p",
           [?MODULE, ?LINE, TrainId, State]),
    case is_may_train(CityId, CitiesId, Max, Numbers) of
        ok ->
            SpendTime = get_spend_time(Type),
            case spend_golds(Type, CityId) of
                ok ->
                    ?DEBUG("~p:handle_call ~p add_train ", [?MODULE, ?LINE]),
                    Pid = spawn_link(?MODULE, train, [Type, CityId, SpendTime]),
                    NewPids = dict:store(Pid, {train, Type, CityId, TrainId, Numbers}, Pids),
                    NewCitiesId = dict:update_counter(CityId, 1, CitiesId),
                    NewTrainsId = dict:store(TrainId, {Pid}, TrainsId),
                    add_soldier(CityId, Numbers, Type, "2"),
                    NewState = State#state{pids = NewPids, 
                                           cities_id = NewCitiesId,
                                           trains_id = NewTrainsId
                                           };
                Error1 ->
                    ?ERROR("~p:handle_call ~p add_train Error1=~p", [?MODULE, ?LINE, Error1]),
                    NewState = State
            end;
        Error ->
            ?ERROR("~p:handle_call ~p add_train Error=~p", [?MODULE, ?LINE, Error]),
            NewState = State
    end,
    {reply, ok, NewState};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({complete, Pid, Type, CityId}, 
            #state{pids=Pids, 
                   cities_id=CitiesId,
                   trains_id=TrainsId }=State) ->
    case dict:is_key(Pid, Pids) of
        true ->
            {train, Type, CityId, TrainId, Numbers} = dict:fetch(Pid, Pids),
            NewCitiesId = dict:update_counter(CityId, -1, CitiesId),
            NewPids = dict:erase(Pid, Pids),
            NewTrainsId = dict:erase(TrainId, TrainsId),
            change_soldier(CityId, Numbers, Type),
            NewState = State#state{pids=NewPids, 
                                   cities_id=NewCitiesId, 
                                   trains_id=NewTrainsId};
        false -> NewState = State
    end,
    {noreply, NewState};
handle_cast(_Request, State) ->
    {noreply, State}.

handle_info({'EXIT', _From, normal}, State) ->
    ?DEBUG("~p:handel_info ~p Reason=~p", [?MODULE, ?LINE, normal]),
    {noreply, State};
handle_info({'EXIT', From, Reason}, 
            #state{pids=Pids, trains_id=TrainsId}=State) ->
    ?DEBUG("~p:handel_info ~p Reason=~p", [?MODULE, ?LINE, Reason]),
    case dict:fetch(From, Pids) of
        {train, Type, CityId, TrainId, Numbers} ->
            SpendTime = get_spend_time(Type),
            Pid = spawn_link(?MODULE, train, [Type, CityId, SpendTime]),
            NewPids = dict:store(Pid, 
                                 {train, Type, CityId, TrainId, Numbers}, 
                                 dict:erase(From, Pids)),
            NewTrainsId =dict:store(TrainId, Pid, TrainsId),
            NewState=State#state{pids = NewPids, trains_id = NewTrainsId}
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


-spec complete(Pid::pid(), Type::string(), CityId::city_id()) -> ok.
complete(Pid, Type, CityId) ->
    gen_server:cast(?SERVER, {complete, Pid, Type, CityId}).

-spec spend_golds(Type::string(), CityId::city_id()) -> 
        ok|{error, Error::term()}.
spend_golds(Type, CityId) ->
    SpendGolds = get_spend_golds(Type),
    ?DEBUG("~p:spend_golds ~p Type=~p, CityId=~p, SpendGolds=~p",
            [?MODULE, ?LINE, Type, CityId, SpendGolds]),
    case mnesia:dirty_read(city, CityId) of
        [] -> 
            {error, "the city not exits"};
        [#city{golds=Golds}=City] when Golds >=SpendGolds ->
            ?DEBUG("~p:spend_golds ~p Type=~p, CityId=~p, SpendGolds=~p, Golds=~p",
            [?MODULE, ?LINE, Type, CityId, SpendGolds, Golds]),
            R = mnesia:dirty_write(City#city{golds = Golds-SpendGolds}),
            ?DEBUG("~p:spend_golds ~p R=~p", [?MODULE, ?LINE, R]),
            ok;
        [#city{golds=Golds}] when Golds <SpendGolds ->
            ?DEBUG("~p:spend_golds ~p Type=~p, CityId=~p, SpendGolds=~p, Golds=~p",
            [?MODULE, ?LINE, Type, CityId, SpendGolds, Golds]),
            {error, "not enough glods"};
        Error ->
            ?ERROR("~p:spend_golds ~p Error=~p", [?MODULE, ?LINE, Error]),
            {error, Error}

    end.
    

-spec is_may_train(CityId::city_id(), Cities::dict(), 
            Max::integer(), Numbers::integer()) ->
            ok|{error, Error::term()}.
is_may_train(CityId, Cities, Max, Numbers) ->
    case is_enough_people_to_train(CityId, Numbers) of
        ok ->
            is_empty(CityId, Cities, Max);
        Error ->
            Error
    end.


-spec is_empty(CityId::city_id(), Cities::dict(), Max::integer()) ->
            ok|{error, Error::term()}.
is_empty(CityId, Cities, Max) ->
    case dict:is_key(CityId, Cities) of
        true ->
            case dict:fetch(CityId, Cities) of
                Value when Value < Max -> 
                    ?DEBUG("~p:is_empty ~p Value=~p", [?MODULE, ?LINE, Value]),
                    ok;
                _IsFull ->
                    ?DEBUG("~p:is_empty ~p _IsFull=~p", [?MODULE, ?LINE, _IsFull]),
                    {error, "is_full"}    
            end;
        false ->
           ok
    end.

-spec is_enough_people_to_train(CityId::city_id(), Numbers::integer()) ->
        ok|{error, Error::term()}.
is_enough_people_to_train(CityId, Numbers) ->
    case mnesia:dirty_read(city, CityId) of
        [] -> {error, "the city is not exists"};
        [#city{peoples=Peoples}=City] when Peoples >= Numbers->
            mnesia:dirty_write(City#city{peoples=Peoples-Numbers}),
            ok;
        [#city{peoples=Peoples}] when Peoples < Numbers->
            {error, "the city is not enough"};
        Error ->
            ?ERROR("~p:is_enough_people_to_train ~p Error=~p", 
                    [?MODULE, ?LINE, Error]),
            {error, Error}
    end.
    
-spec change_soldier(CityId::city_id(), Numbers::integer(), Type::string()) ->
        ok|{error, Error::term()}.
change_soldier(CityId, Numbers, Type) ->
    ?DEBUG("~p:change_soldier ~p", [?MODULE, ?LINE]),
    case mnesia:dirty_read(soldier, {CityId, "2", Type}) of
        [] -> ok;
        [#soldier{sum=Sum}=Soldier] when Sum >=Numbers ->
            mnesia:dirty_write(Soldier#soldier{sum=Sum-Numbers}),
            add_soldier(CityId, Numbers, Type, "3");
        [#soldier{sum=Sum}=Soldier] when Sum <Numbers ->
            mnesia:dirty_write(Soldier#soldier{sum=0}),
            add_soldier(CityId, Numbers, Type, "3")
    end.

-spec add_soldier(CityId::city_id(), Numbers::integer(), 
                  Type::string(), State::string()) ->
        ok|{error, Error::term()}.
add_soldier({_, AuthorId}=CityId, Numbers, Type, State) ->
    case mnesia:dirty_read(soldier, {CityId, State, Type}) of
        [] ->
            Soldier = #soldier{id={CityId, State, Type},
                               author_id_state={AuthorId, State},
                               author_id = AuthorId,
                               city_id = CityId,
                               type=Type,
                               state = State,
                               sum=Numbers,
                               time=calendar:local_time()
                               },
            mnesia:dirty_write(Soldier);
        [#soldier{sum=Sum}=Soldier] ->
            NewSoldier = 
                Soldier#soldier{id={CityId, State, Type},
                                author_id = AuthorId,
                                author_id_state={AuthorId, State},
                                city_id = CityId,
                                type=Type,
                                state = State,
                                sum=Numbers+Sum},
            mnesia:dirty_write(NewSoldier)
    end.
        
consumer_food() ->
    Key = mnesia:dirty_first(soldier),
    consumer_food1(Key).
consumer_food1('$end_of_table') ->
    ok;
consumer_food1(Id) ->
    case mnesia:dirty_read(soldier, Id) of
        [#soldier{type=Type, state="3", sum=Sum, city_id=CityId}] ->
            consumer_food(Type, Sum, CityId);
        _Other -> ok
    end,
    Key = mnesia:dirty_next(soldier, Id),
    consumer_food1(Key).
    
-spec consumer_food(Type::string(), Sum::integer(), CityId::city_id()) ->ok.
consumer_food(Type, Sum, CityId) ->
    ConsumerFoods = get_consumer_food(Type) * Sum,
    case mnesia:dirty_read(city, CityId) of
        [#city{foods=Foods}=City] when Foods>=ConsumerFoods->
            mnesia:dirty_write(City#city{foods=Foods-ConsumerFoods});
        [#city{foods=Foods}=City] when Foods<ConsumerFoods->
            mnesia:dirty_write(City#city{foods=0})
    end.

get_consumer_food("1") ->
    10;
get_consumer_food("2") ->
    13;
get_consumer_food("3") ->
    30.
    


get_spend_golds("1") ->
    1;
get_spend_golds("2") ->
    3;
get_spend_golds("3") ->
    10.

get_spend_time("1") ->
    3*60*?SPEND_TIME;
get_spend_time("2") ->
    12*60*?SPEND_TIME;
get_spend_time("3") ->
    50*60*?SPEND_TIME.
    



-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-ifdef(TEST).

respawn_test1() -> application:start(game),
    X = 3, Y=3, AuthorId = "langxw",
    Y2 = 2,
    CityNotExists = add_train("1", {{X, Y}, AuthorId}, "1", 5),
    %receive after 2000 -> ok end,
    simple_server:create_city({X, Y}, AuthorId),
    simple_server:create_city({X, Y2}, AuthorId),
    add_golds({{X, Y}, AuthorId}, 1),
    NotEnoughGlods = add_train("2", {{X, Y}, AuthorId}, "2", 5),
    add_golds({{X, Y}, AuthorId}, 23),
    CityId = {{X, Y}, AuthorId},
    ok = add_train("1", {{X, Y}, AuthorId}, "3", 5),
    ok = add_train("3", {{X, Y}, AuthorId}, "4", 5),
    ok = add_train("1", {{X, Y}, AuthorId}, "5", 5),
    ok = add_train("1", {{X, Y}, AuthorId}, "6", 500),
    ok = add_train("2", {{X, Y}, AuthorId}, "7", 5),
    ok = add_train("2", {{X, Y}, AuthorId}, "8", 5),
    ok = add_train("1", {{X, Y}, AuthorId}, "9", 5),
    get_soldier_for_city(CityId),
    receive after 3*60*?SPEND_TIME -> ok end,
    ok = add_train("3", {{X, Y}, AuthorId}, "10", 5),
    get_soldier_for_city(CityId),
    ok = add_train("1", {{X, Y}, AuthorId}, "11", 5),
    get_soldier_for_city(CityId),
    cancel_train("3", {{X, Y}, AuthorId}, "4"),
    cancel_train("1", {{X, Y}, AuthorId}, "11"),
    complete(self(), "1", {{X, Y}, AuthorId}),
    cancel_train("4", {{X, Y2}, AuthorId}, "10"),
    receive after 1000 -> ok end,
    [?assertMatch(ok, ok),
     ?assertMatch(1,1)
    ].

-endif.

