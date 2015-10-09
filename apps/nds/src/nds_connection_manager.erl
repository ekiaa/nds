-module(nds_connection_manager).

-behaviour(gen_server).

%% API functions

-export([start_link/0, get_connection/2]).

%% gen_server callbacks

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(TABLE, nds_connection_db).

%-------------------------------------------------------------------------------

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

get_connection(ID, Token) ->
	Key = {ID, Token},
	case ets:lookup(?TABLE, Key) of
		[] ->
			gen_server:call(?MODULE, {create_connection, Key});
		[{Key, Connection}] ->
			Connection
	end.

%-------------------------------------------------------------------------------

init([]) ->
	ets:new(?TABLE, [named_table, protected, {read_concurrency, true}]),
	lager:debug("[init] ets table ~p created", [?TABLE]),
	{ok, #{keys => #{}}};

init(Args) ->
	lager:error("[init] Args: ~p", [Args]),
	{stop, {error, {?MODULE, ?LINE, Args}}}.

%-------------------------------------------------------------------------------

handle_call({create_connection, Key}, _, #{keys := Keys} = State) ->
	{ok, Connection} = nds_connection:start(Key),
	ets:insert(?TABLE, {Key, Connection}),
	monitor(process, Connection),
	{reply, Connection, State#{keys => maps:put(Connection, Key, Keys)}};

handle_call(Request, From, State) ->
	lager:error("[handle_call] From: ~p; Request: ~p", [From, Request]),
	Error = {error, {?MODULE, ?LINE, {From, Request}}},
	{stop, Error, Error, State}.

%-------------------------------------------------------------------------------

handle_cast(Message, State) ->
	lager:error("[handle_cast] Message: ~p", [Message]),
	{stop, {error, {?MODULE, ?LINE, Message}}, State}.

%-------------------------------------------------------------------------------

handle_info({'DOWN', _, _, Connection, Reason}, #{keys := Keys} = State) ->
	case maps:get(Connection, Keys, undefined) of
		undefined ->
			% lager:debug("[handle_info] not matched Process ~p down with ~p", [Connection, Reason]),
			{noreply, State};
		Key ->
			% lager:debug("[handle_info] Connection ~p down with ~p", [Connection, Reason]),
			ets:delete(?TABLE, Key),
			{noreply, State#{ids => maps:remove(Connection, Keys)}}
	end;

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