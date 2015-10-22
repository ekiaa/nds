%%%-------------------------------------------------------------------
%% @doc nds public API
%% @end
%%%-------------------------------------------------------------------

-module('nds_app').

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
	Dispatch  = cowboy_router:compile([{'_', [
		{"/:queue_name/:subscriber_name", nds_http_handler, []},
		{"/:queue_name", nds_http_handler, []}
	]}]),
	Listeners = application:get_env(nds, listeners, 100),
	Port = application:get_env(nds, port, 8080),
	Options = [
		{port, Port},
		{max_connections, infinity}
	],
	_Res = cowboy:start_http(nds_http_listener, Listeners, Options, [{env, [{dispatch, Dispatch}]}]),
	lager:debug("[start] cowboy:start_http() return: ~p; Port: ~p", [_Res, Port]),
    'nds_sup':start_link().

%%--------------------------------------------------------------------
stop(_State) ->
	_Res = cowboy:stop_listener(nds_http_listener),
	lager:debug("[stop] cowboy:stop_listener(nds_http_listener) return: ~p", [_Res]),
    ok.

%%====================================================================
%% Internal functions
%%====================================================================
