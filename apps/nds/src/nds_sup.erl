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
		{nds_manager, {nds_manager, start_link, []}, permanent, 5000, worker, [nds_manager]},
		{nds_subscriber_sup, {nds_subscriber_sup, start_link, []}, permanent, infinity, supervisor, [nds_subscriber_sup]},
		{nds_subscriber_manager, {nds_subscriber_manager, start_link, []}, permanent, 5000, worker, [nds_subscriber_manager]},
		{nds_publisher_sup, {nds_publisher_sup, start_link, []}, permanent, infinity, supervisor, [nds_publisher_sup]},
		{nds_publisher_manager, {nds_publisher_manager, start_link, []}, permanent, 5000, worker, [nds_publisher_manager]}
	]}}.

%%====================================================================
%% Internal functions
%%====================================================================
