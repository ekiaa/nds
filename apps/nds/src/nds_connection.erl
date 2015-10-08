-module(nds_connection).

-behaviour(gen_server).

%% API functions

-export([start/2, start_link/2, get/2]).

%% gen_server States

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%-------------------------------------------------------------------------------

start(Connection, Token) ->
	nds_connection_sup:start_child([Connection, Token]).

start_link(Connection, Token) ->
	gen_server:start_link(?MODULE, {Connection, Token}, []).

get(Connection, Token) ->
	lager:debug("[get] Connection: ~p; Token: ~p", [Connection, Token]),
	case catch gproc:lookup_local_name({?MODULE, Connection}) of
		Pid when is_pid(Pid) ->
			gen_server:cast(Pid, {get, self()});
		Result1 ->
			lager:debug("[get] gproc:lookup_local_name() return: ~p", [Result1]),
			case catch ?MODULE:start(Connection, Token) of
				{ok, Pid} ->
					gen_server:cast(Pid, {get, self()});
				Result2 ->
					lager:debug("[get] start(Connection, Token) return: ~p; Connection: ~p; Token: ~p", [Result2, Connection, Token]),
					Result2
			end
	end.

%-------------------------------------------------------------------------------

init({Connection, Token}) ->
	lager:debug("[init] Token: ~p", [Token]),
	case catch gproc:add_local_name({?MODULE, Connection}) of
		true ->
			lager:debug("[init] started"),
			nds_queue:subscribe(Token),
			Timestamp = now(),
			timer:send_interval(30000, check_timestamp),
			{ok, #{connection => Connection, token => Token, clients => [], events => queue:new(), timestamp => Timestamp}};
		Result ->
			lager:debug("[init] gproc:add_local_name() return: ~p", [Result]),
			{stop, already_registered}
	end;

init(Args) ->
	lager:error("[init] Args: ~p", [Args]),
	{stop, {error, {?MODULE, ?LINE, Args}}}.

%-------------------------------------------------------------------------------

handle_call(Request, From, State) ->
	lager:error("[handle_call] From: ~p; Request: ~p", [From, Request]),
	Error = {error, {?MODULE, ?LINE, {From, Request}}},
	{stop, Error, Error, State}.

%-------------------------------------------------------------------------------

handle_cast({get, NewClient}, #{token := Token, clients := Clients, events := Events} = State) ->
	case queue:out(Events) of
		{empty, _} ->
			lager:debug("[handle_call] get: no events; Client: ~p", [NewClient]),
			{noreply, State#{clients => [NewClient | Clients], timestamp => now()}};
		{{value, FrontEvent}, RestEvents} ->
			lager:debug("[handle_info] get: send front event to Clients; Token: ~p; Event: ~p; Clients: ~p", [Token, FrontEvent, [NewClient | Clients]]),
			[Client ! {event, FrontEvent} || Client <- [NewClient | Clients]],
			{noreply, State#{clients => [], events => RestEvents, timestamp => now()}}
	end;

handle_cast(Message, State) ->
	lager:error("[handle_cast] Message: ~p", [Message]),
	{stop, {error, {?MODULE, ?LINE, Message}}, State}.

%-------------------------------------------------------------------------------

handle_info({event, Event}, #{token := Token, clients := [], events := Events} = State) ->
	lager:debug("[handle_info] post: no clients; Token: ~p; Event: ~p", [Token, Event]),
	{noreply, State#{events => queue:in(Event, Events)}};

handle_info({event, Event}, #{token := Token, clients := Clients, events := Events} = State) ->
	case queue:out(Events) of
		{empty, _} ->
			lager:debug("[handle_info] post; Token: ~p; Event: ~p; Clients: ~p", [Token, Event, Clients]),
			[Client ! {event, Event} || Client <- Clients],
			{noreply, State#{clients => [], timestamp => now()}};
		{{value, FrontEvent}, RestEvents} ->
			lager:debug("[handle_info] send front event to Clients; Token: ~p; Event: ~p; Clients: ~p", [Token, Event, Clients]),
			[Client ! {event, FrontEvent} || Client <- Clients],
			{noreply, State#{clients => [], events => queue:in(Event, RestEvents), timestamp => now()}}
	end;

handle_info(check_timestamp, #{clients := [], timestamp := Timestamp, connection := Connection, token := Token} = State) ->
	case timer:now_diff(now(), Timestamp) of
		Tdiff when Tdiff > 120000000 ->
			lager:debug("[handle_info] check_timestamp: time is up; Connection: ~p; Token: ~p; Tdiff: ~p", [Connection, Token, Tdiff]),
			nds_queue:unsubscribe(Token),
			{stop, normal, State};
		Tdiff ->
			lager:debug("[handle_info] check_timestamp; Connection: ~p; Token: ~p; Tdiff: ~p", [Connection, Token, Tdiff]),
			{noreply, State}
	end;

handle_info(check_timestamp, #{connection := Connection, token := Token, clients := Clients} = State) ->
	lager:debug("[handle_info] check_timestamp; Connection: ~p; Token: ~p; Clients: ~p", [Connection, Token, Clients]),
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