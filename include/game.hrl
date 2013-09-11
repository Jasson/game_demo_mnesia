-define(DEBUG(Input, Args), 
        error_logger:info_msg(Input ++ "~n", Args)).
%-define(DEBUG(Input, Args), "").

-define(ERROR(Input, Args), 
        error_logger:error_msg(Input ++ "~n", Args)).

-define(PRODUCT_FOOD_TIME, 1000).
-define(CONSUMER_FOOD_TIME, 1000).
-define(COLLECT_TAXES_TIME, 2000).

-record(map, {id={{0,0}, author_id=""}, is_empty="1"}).
-record(city, {id={{0,0}, author_id=""}, 
               name="cityname", 
               author_id="jaons_id", 
               foods=0.0, 
               product_food_rate=1000/60/60, 
               golds=0.0,
               gold_tax=0.2, 
               peoples=100, 
               soldiers=0,
               is_capital="0"}).

%% type:兵种类型
%% state:此兵种状态，训练，训练完成，前进，回城,战斗
-record(soldier, {id={"","", ""}::{CityId::city_id(), 
                                   State::string(),
                                   Type ::string()},
                  author_id_state=""::{AuthorId::string(), 
                                       State::string()},
                  author_id=""::string(),
                  city_id=#city.id :: tuple(), 
                  type="1" :: string(),%%1:长枪兵 2:弓箭手 3:骑兵
                  %% 0:leisure 1:wait 2:training 3:complete 4:forward 5:back 6:battle
                  state="0" :: string(), 
                  sum=0,
                  time=calendar:local_time()}).
%-record(battle, {id={"", ""}::{CityId::city_id(), integer()},
%                 city_id=#city.id::city_id(),
%                 soldier_type=#soldier.type::string(),
%                 state=""::string(), %% 0:forward 1:back 2:battle
%                 sum=0
%                 }).


-type city() :: #city{}.
-type city_id() :: {{integer(), integer()}, string()}. %%City=#city.id.
-type soldier() :: #soldier{}.
-type soldier_type() :: string().

