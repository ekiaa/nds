-module(nds_connection_sup).

-behaviour(supervisor).

%% API
-export([start_link/0, start_child/1]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_child(Params) ->
	supervisor:start_child(?MODULE, Params).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    {ok, {{simple_one_for_one, 1000, 1}, [
    	{nds_connection, {nds_connection, start_link, []}, temporary, 5000, worker, [nds_connection]}
    ]}}.

