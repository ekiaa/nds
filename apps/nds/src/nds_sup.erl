%%%-------------------------------------------------------------------
%% @doc nds top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module('nds_sup').

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
    {ok, {{one_for_all, 0, 1}, [
    	{nds_queue_sup, {nds_queue_sup, start_link, []}, permanent, infinity, supervisor, [nds_queue_sup]},
    	{nds_connection_sup, {nds_connection_sup, start_link, []}, permanent, infinity, supervisor, [nds_connection_sup]}
    ]}}.

%%====================================================================
%% Internal functions
%%====================================================================
