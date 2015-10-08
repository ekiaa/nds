-module(nds_connection).

-behaviour(gen_server).

%% API functions

-export([start/1, start_link/1, get/2, close/2]).

%% gen_server States

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%-------------------------------------------------------------------------------

start(Params) ->
	nds_connection_sup:start_child([Params]).

start_link(Params) ->
	gen_server:start_link(?MODULE, Params, []).

get(ID, Token) ->
	lager:debug("[get] ID: ~p; Token: ~p", [ID, Token]),
	Connection = nds_connection_manager:get_connection(ID, Token),
	gen_server:cast(Connection, {get, self()}).

close(ID, Token) ->
	lager:debug("[close] ID: ~p; Token: ~p", [ID, Token]),
	Connection = nds_connection_manager:get_connection(ID, Token),
	gen_server:cast(Connection, {close, self()}).

%-------------------------------------------------------------------------------

init({ID, Token}) ->
	lager:debug("~p => init -> ~p", [ID, Token]),
	nds_queue:subscribe(Token),
	Timestamp = now(),
	timer:send_interval(30000, check_timestamp),
	{ok, #{id => ID, token => Token, clients => [], messages => queue:new(), timestamp => Timestamp}};

init(Args) ->
	lager:error("[init] Args: ~p", [Args]),
	{stop, {error, {?MODULE, ?LINE, Args}}}.

%-------------------------------------------------------------------------------

handle_call(Request, From, State) ->
	lager:error("[handle_call] From: ~p; Request: ~p", [From, Request]),
	Error = {error, {?MODULE, ?LINE, {From, Request}}},
	{stop, Error, Error, State}.

%-------------------------------------------------------------------------------

handle_cast({get, NewClient}, #{id := ID, token := Token, clients := Clients, messages := Messages} = State) ->
	case queue:out(Messages) of
		{empty, _} ->
			lager:debug("~p => get from ~p -> no messages; Client: ~p", [ID, Token, NewClient]),
			{noreply, State#{clients => [NewClient | Clients], timestamp => now()}};
		{{value, FrontMessage}, RestMessages} ->
			lager:debug("~p => get from ~p -> ~p; Clients: ~p", [ID, Token, FrontMessage, [NewClient | Clients]]),
			[Client ! {event, FrontMessage} || Client <- [NewClient | Clients]],
			{noreply, State#{clients => [], messages => RestMessages, timestamp => now()}}
	end;

handle_cast({close, Client}, #{id := ID, clients := Clients} = State) ->
	lager:debug("~p => closed -> ~p", [ID, Client]),
	{noreply, State#{clients => lists:delete(Client, Clients)}};

handle_cast(Message, State) ->
	lager:error("[handle_cast] Message: ~p", [Message]),
	{stop, {error, {?MODULE, ?LINE, Message}}, State}.

%-------------------------------------------------------------------------------

handle_info({publish, Message}, #{id := ID, token := Token, clients := [], messages := Messages} = State) ->
	lager:debug("~p => publish in ~p -> no clients; Message: ~p", [ID, Token, Message]),
	{noreply, State#{messages => queue:in(Message, Messages)}};

handle_info({publish, Message}, #{id := ID, token := Token, clients := Clients} = State) ->
	lager:debug("~p => publish in ~p -> ~p; Message: ~p", [ID, Token, Clients, Message]),
	[Client ! {message, Message} || Client <- Clients],
	{noreply, State#{clients => [], timestamp => now()}};

handle_info(check_timestamp, #{clients := [], timestamp := Timestamp, id := ID} = State) ->
	case timer:now_diff(now(), Timestamp) of
		Tdiff when Tdiff > 120000000 ->
			lager:debug("~p => check_timestamp -> become rotten; Tdiff: ~p", [ID, Tdiff]),
			{stop, normal, State};
		Tdiff ->
			lager:debug("~p => check_timestamp -> fresh; Tdiff: ~p", [ID, Tdiff]),
			{noreply, State}
	end;

handle_info(check_timestamp, #{id := ID, clients := Clients} = State) ->
	lager:debug("~p => check_timestamp -> not empty; Clients: ~p", [ID, Clients]),
	{noreply, State};

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