-module(battle).
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
         to_battle/5,
         send_soldier/5
         ]).

-record(state, {pids = dict:new(), 
                cities_id =dict:new(),
                max=5}).
%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

-spec send_soldier(From::city_id(), To::city_id(), 
                   PikeSoldier::{soldier_type(), integer()}, 
                   ArcherSoldier::{soldier_type(), integer()}, 
                   Cavalry::{soldier_type(), integer()}) ->
              ok|{error, term()}.
send_soldier(From, To, PikeSoldier, ArcherSoldier, Cavalry) ->
    Request = 
        {send_soldier, From, To, PikeSoldier, ArcherSoldier, Cavalry},
    gen_server:call(?SERVER, Request).
    

-spec to_battle(FromCityId::city_id(), ToCityId::city_id(),
                PikeSoldier::{soldier_type(), integer()}, 
                ArcherSoldier::{soldier_type(), integer()}, 
                Cavalry::{soldier_type(), integer()}) ->
        ok|{error, term()}.
to_battle(FromCityId, ToCityId, PikeSoldier, ArcherSoldier, Cavalry) ->
    Distance = get_distance(FromCityId, ToCityId),
    SpendTime = get_spend_time(Distance, PikeSoldier, ArcherSoldier, Cavalry),
    ?DEBUG("~p:to_battle ~p SpendTime=~p", [?MODULE, ?LINE, SpendTime]),
    receive 
        cancle_battle ->
            %%TODO
            ok
    after SpendTime ->
        join_battle(ToCityId),
        [kill_soldier(FromCityId, ToCityId) ||_N<-lists:seq(1,10)],
        receive 
        after SpendTime ->
            to_back(FromCityId),
            complete(self(), FromCityId)
        end
    end.
    
complete(Pid, CityId) ->
    gen_server:cast(?SERVER, {complete, Pid, CityId}).
%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) ->
    ?DEBUG("~p:init ~p ", [?MODULE, ?LINE]),
    process_flag(trap_exit, true),
    {ok, #state{}}.

handle_call({send_soldier, FromCity, ToCity, PikeSoldier, 
             ArcherSoldier, Cavalry}, _From, 
             #state{max=Max, pids=Pids, cities_id=CitiesId}=State) ->
    ?DEBUG("~p:handle_call ~p send_soldier state=~p", [?MODULE, ?LINE, State]),
    case is_may_battle(FromCity, PikeSoldier, ArcherSoldier, Cavalry, CitiesId, Max) of
        ok ->
            Args = [FromCity, ToCity, PikeSoldier, ArcherSoldier, Cavalry],
            Pid = spawn_link(?MODULE, to_battle, Args),
            NewPids = dict:store(Pid, {send_soldier, Args}, Pids),
            NewCitiesId = dict:update_counter(FromCity, 1, CitiesId),
            NewState = State#state{pids=NewPids, cities_id=NewCitiesId};
        {error, _Error} ->
            NewState = State
        end,
    {reply, ok, NewState};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({complete, Pid, CityId}, #state{pids=Pids, cities_id=CitiesId}=State) ->
    NewPids = dict:erase(Pid, Pids),
    NewCitiesId = dict:update_counter(CityId, -1, CitiesId),
    NewState = State#state{pids=NewPids, cities_id=NewCitiesId},
    {noreply, NewState};
handle_cast(_Request, State) ->
    {noreply, State}.

handle_info({'EXIT', _From, normal}, State) ->
    ?DEBUG("~p:handel_info ~p Reason=~p", [?MODULE, ?LINE, normal]),
    {noreply, State};
handle_info({'EXIT', From, Reason}, #state{pids=Pids}=State) ->
    ?DEBUG("~p:handel_info ~p Reason=~p", [?MODULE, ?LINE, Reason]),
    {send_soldier, Args} = dict:fetch(From, Pids),
    Pid = spawn_link(?MODULE, to_battle, Args),
    NewPids = dict:store(Pid, {send_soldier, Args}, 
                         dict:erase(From, Pids)),
    NewState = State#state{pids=NewPids},
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

-spec is_may_battle(CityId::city_id(), 
                    PikeSoldier::{string(), integer()},
                    ArcherSoldier::{string(), integer()},
                    Cavalry::{string(), integer()},
                    CitiesId::dict(),
                    Max::integer()) -> ok |{error, term()}.
    
is_may_battle(CityId, PikeSoldier, ArcherSoldier, Cavalry, CitiesId, Max) ->
    case train_soldier:is_empty(CityId, CitiesId, Max) of
        ok ->
            is_enough_soldier_to_battle(CityId, PikeSoldier, ArcherSoldier, Cavalry);
        Error ->
            ?DEBUG("~p:is_may_battle ~p Error=~p", [?MODULE, ?LINE, Error]),
            Error
    end.
    
-spec is_enough_soldier_to_battle(
            CityId::city_id(),
            PikeSoldier::{string(),integer()}, 
            ArcherSoldier::{string(),integer()}, 
            Cavalry::{string(),integer()})-> ok |{error, term()}.
is_enough_soldier_to_battle(CityId, PikeSoldier, ArcherSoldier, Cavalry) ->
    case {get_soldier(CityId, PikeSoldier), 
          get_soldier(CityId, ArcherSoldier),
          get_soldier(CityId, Cavalry)} of
          {ok, ok, ok} ->
             ok;
          Error ->
             ?DEBUG("~p:is_enough_soldier_to_battle ~p Error=~p", [?MODULE, ?LINE, Error]),
             {error, Error}
    end.
-spec get_soldier(CityId::city_id(), 
                  Soldier::{soldier_type(), integer()}) -> 
            ok|{error, term()}.

get_soldier(_CityId, {_Type, 0}) ->
    ok;
get_soldier(CityId, {Type, Num}) ->
    case mnesia:dirty_read(soldier, {CityId, "3", Type}) of
        [] -> {error, "not enough "++Type};
        [#soldier{sum=Sum}=Soldier] when Num=<Sum ->
            to_forward(Soldier, Num, Sum),
            ok;
        [#soldier{sum=Sum}] when Num>Sum ->
            {error, "not enough "++Type};
        Error ->
            {error, Error}
        
    end.
-spec to_forward(Soldier::soldier(), Num::integer(), Sum::integer()) ->ok.

to_forward(Soldier, Num, Sum) ->
    ?DEBUG("~p:to_forward ~p Num=~p, Sum=~p, Soldier=~p", 
            [?MODULE, ?LINE, Num, Sum, Soldier]),
    Type = Soldier#soldier.type,
    CityId = Soldier#soldier.city_id,
    AuthorId = Soldier#soldier.author_id,
    State = "6",
    AuthorIdState = {AuthorId, State},
    mnesia:dirty_write(Soldier#soldier{sum=Sum-Num}),
    ForwardSoldier = Soldier#soldier{id={CityId, State, Type},
                                     author_id_state=AuthorIdState,
                                     state=State,
                                     sum=Num},
    mnesia:dirty_write(ForwardSoldier).

-spec join_battle(CityId::city_id()) -> ok|{error, term()}.
join_battle(CityId) ->
    %% TODO send battle notice
    Soldiers = mnesia:dirty_index_read(soldier, CityId, city_id),
    Fun = fun(#soldier{id={_, "3", Type}, 
                       author_id=AuthorId, 
                       state="3"}=Soldier) ->
              NewSoldier = 
                  Soldier#soldier{id={CityId, "6", Type},
                                  author_id_state={AuthorId, "6"},
                                  state=6
                                 },
              mnesia:dirty_write(NewSoldier);
              (_Soldier) -> ok
          end,
    lists:foreach(Fun, Soldiers).

-spec get_distance(FromCityId::city_id(), ToCityId::city_id()) -> float().
get_distance({{X1, Y1}, _}, {{X2, Y2}, _}) ->
    math:sqrt((X1-X2)*(X1-X2)+(Y1-Y2)*(Y1-Y2)).
    

get_spend_time(Distance, PikeSoldier, ArcherSoldier, Cavalry) -> 
    Time =  
        case Cavalry of
            {_, 0} ->
                60/2;
            _Other1 ->
                60/10
        end,
    Time1 = 
        case ArcherSoldier of
            {_, 0} ->
                Time;
            _Other2 ->
                60/2
        end,
    Time3 = 
        case PikeSoldier of
            {_, 0} ->
                Time1;
            _Other3 ->
                60/1.5
        end, 
    %%Distance * Time3.
    trunc(Distance * Time3*10).  %TODO
     



kill_soldier(From, To) ->
    Random = random:uniform(2),
    kill_soldier(From, To, Random).

kill_soldier(_From, To, 1) ->
    kill_soldier(To);
kill_soldier(From, _To, 2) ->
    kill_soldier(From).

kill_soldier(CityId) ->
    %%TODO ignore back time
    Type = get_random_type(),
    case mnesia:dirty_read(soldier, {CityId, "6", Type}) of
        [#soldier{sum=Sum}=Soldier] when Sum=<0->
            ?DEBUG("~p:kill_soldier ~p Soldier =~p", [?MODULE, ?LINE, Soldier]),
            mnesia:dirty_write(Soldier#soldier{sum=0});
        [#soldier{sum=Sum}=Soldier] when Sum>0->
            ?DEBUG("~p:kill_soldier ~p Soldier =~p", [?MODULE, ?LINE, Soldier]),
            mnesia:dirty_write(Soldier#soldier{sum=Sum-1});
        Error ->
            ?DEBUG("~p:kill_soldier ~p Error =~p", [?MODULE, ?LINE, Error]),
            ok
    end.

get_random_type() ->
    Random = random:uniform(3),
    integer_to_list(Random).
    
    
-spec to_back(CityId::city_id()) -> ok.
to_back(CityId) ->
    Soldiers =  mnesia:dirty_index_read(soldier, CityId, city_id),
    Fun = fun(#soldier{type=Type, state="6", sum=Num}=Soldier) ->
                  mnesia:dirty_write(Soldier#soldier{sum=0}),
                  case mnesia:dirty_read(soldier, {CityId, "3", Type}) of
                      [#soldier{sum=Sum}=OrgSoldier] ->
                          mnesia:dirty_write(OrgSoldier#soldier{sum=Sum+Num})
                  end;
             (_Soldier) ->
                ok
          end,
    lists:foreach(Fun, Soldiers).


-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-ifdef(TEST).

respawn_test() -> 
    application:start(game),
    X4 = 4, Y4=4, 
    AuthorId4 = "langxw",
    X9=9, Y9 = 9,
    AuthorId9 = "langxw9",
    CityId = {{X4, Y4}, AuthorId4},
    From = CityId,
    To = {{X9, Y9}, AuthorId9},
    simple_server:create_city({X4, Y4}, AuthorId4),
    City44 = simple_server:get_city({X4, Y4}, AuthorId4),
    simple_server:change_peoples(City44#city{golds=1000.0}),
    simple_server:create_city({X9, Y9}, AuthorId9),
    City99 = simple_server:get_city({X9, Y9}, AuthorId9),
    simple_server:change_peoples(City99#city{golds=1000.0}),
    train_soldier:add_train("1", From, "1", 5),
    train_soldier:add_train("2", From, "2", 5),
    train_soldier:add_train("3", From, "3", 5),
    train_soldier:add_train("1", To, "1", 5),
    train_soldier:add_train("2", To, "2", 5),
    train_soldier:add_train("3", To, "3", 5),
    receive after 2000 -> ok end,
    train_soldier:get_soldier_for_city(From),
    train_soldier:get_soldier_for_city(To),
    send_soldier(From, To, {"1",1}, {"2",1}, {"3",0}),
    send_soldier(From, To, {"1",0}, {"2",1}, {"3",0}),
    receive after 1000 -> ok end,
    train_soldier:get_soldier_for_city(From),
    train_soldier:get_soldier_for_city(To),
    %kill_soldier(To, From),
    %kill_soldier(To, From),
    %kill_soldier(To, From),
    receive after 1000 -> ok end,
    [?assertMatch(ok, ok),
     ?assertMatch(1,1)
    ].

-endif.

