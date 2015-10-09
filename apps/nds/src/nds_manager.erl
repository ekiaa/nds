-module(nds_manager).

-behaviour(gen_server).

%% API functions

-export([start_link/0, increment/0, decrement/0]).

%% gen_server callbacks

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%-------------------------------------------------------------------------------

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

increment() ->
	gen_server:cast(?MODULE, increment).

decrement() ->
	gen_server:cast(?MODULE, decrement).

%-------------------------------------------------------------------------------

init([]) ->
	lager:debug("[init]"),
	{ok, #{count => 0}};

init(Args) ->
	lager:error("[init] Args: ~p", [Args]),
	{stop, {error, {?MODULE, ?LINE, Args}}}.

%-------------------------------------------------------------------------------

handle_call(Request, From, State) ->
	lager:error("[handle_call] From: ~p; Request: ~p", [From, Request]),
	Error = {error, {?MODULE, ?LINE, {From, Request}}},
	{stop, Error, Error, State}.

%-------------------------------------------------------------------------------

handle_cast(increment, #{count := Count} = State) ->
	NewCount = Count + 1,
	lager:debug("Count: ~p", [NewCount]),
	{noreply, State#{count => NewCount}};

handle_cast(decrement, #{count := Count} = State) ->
	NewCount = Count - 1,
	lager:debug("Count: ~p", [NewCount]),
	{noreply, State#{count => NewCount}};

handle_cast(Message, State) ->
	lager:error("[handle_cast] Message: ~p", [Message]),
	{stop, {error, {?MODULE, ?LINE, Message}}, State}.

%-------------------------------------------------------------------------------

handle_info(Info, State) ->
	lager:error("[handle_info] Info: ~p", [Info]),
	{stop, {error, {?MODULE, ?LINE, Info}}, State}.

%-------------------------------------------------------------------------------

terminate(Reason, State) -> 
	case Reason of
		normal -> ok;
		_ -> lager:error("[terminate] Reason: ~p; State: ~p", [Reason, State]), ok
	end.

%-------------------------------------------------------------------------------

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.