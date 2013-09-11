
-module(game_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    SimpleServer = {simple_server, 
                    {simple_server, start_link, []},
                    permanent,
                    5000,
                    worker,
                    [simple_server]},
    TrainSoldier = {train_soldier,
                    {train_soldier, start_link, []},
                     permanent,
                     5000,
                     worker,
                     [train_soldier]},
    Battle = {battle,
              {battle, start_link, []},
              permanent,
              5000,
              worker,
              [battle]},
    Process = [TrainSoldier, SimpleServer, Battle],
    %Process = [],
    {ok, { {one_for_one, 5, 10}, Process} }.

