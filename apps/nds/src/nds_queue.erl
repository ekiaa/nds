-module(nds_queue).

-behaviour(gen_server).

%% API functions

-export([start/1, start_link/1, get/1, post/2]).

%% gen_server States

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%-------------------------------------------------------------------------------

start(Token) ->
	nds_queue_sup:start_child([Token]).

start_link(Token) ->
	gen_server:start_link(?MODULE, {token, Token}, []).

get(Token) ->
	lager:debug("[get] Token: ~p", [Token]),
	case catch gproc:lookup_local_name({?MODULE, Token}) of
		Pid when is_pid(Pid) ->
			gen_server:cast(Pid, {get, self()});
		Result1 ->
			lager:debug("[get] gproc:lookup_local_name() return: ~p", [Result1]),
			case catch ?MODULE:start(Token) of
				{ok, Pid} ->
					gen_server:cast(Pid, {get, self()});
				Result2 ->
					lager:debug("[get] start(Token) return: ~p; Token: ~p", [Result2, Token]),
					Result2
			end
	end.

post(Token, Event) ->
	lager:debug("[post] Token: ~p; Event: ~p", [Token, Event]),
	case catch gproc:lookup_local_name({?MODULE, Token}) of
		_Pid when is_pid(_Pid) ->
			send_event(Token, Event);
		Result1 ->
			lager:debug("[post] gproc:lookup_local_name() return: ~p", [Result1]),
			case catch ?MODULE:start(Token) of
				{ok, _Pid} ->
					send_event(Token, Event);
				Result2 ->
					lager:debug("[post] start(Token) return: ~p; Token: ~p", [Result2, Token]),
					Result2
			end
	end.

send_event(Token, Event) ->
	case catch gproc:bcast([node() | nodes()], {n, l, {?MODULE, Token}}, {post, Event}) of
		Result -> lager:debug("[send_event] gproc:bcast() return: ~p", [Result]), ok
	end.

%-------------------------------------------------------------------------------

init({token, Token}) ->
	lager:debug("[init] Token: ~p", [Token]),
	case catch gproc:add_local_name({?MODULE, Token}) of
		true ->
			lager:debug("[init] started"),
			{ok, #{token => Token, clients => [], events => queue:new()}};
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
			{noreply, State#{clients => [NewClient | Clients]}};
		{{value, FrontEvent}, RestEvents} ->
			lager:debug("[handle_info] get: send front event to Clients; Token: ~p; Event: ~p; Clients: ~p", [Token, FrontEvent, [NewClient | Clients]]),
			[Client ! {event, FrontEvent} || Client <- [NewClient | Clients]],
			{noreply, State#{clients => [], events => RestEvents}}
	end;

handle_cast(Message, State) ->
	lager:error("[handle_cast] Message: ~p", [Message]),
	{stop, {error, {?MODULE, ?LINE, Message}}, State}.

%-------------------------------------------------------------------------------

handle_info({post, Event}, #{token := Token, clients := [], events := Events} = State) ->
	lager:debug("[handle_info] post: no clients; Token: ~p; Event: ~p", [Token, Event]),
	{noreply, State#{events => queue:in(Event, Events)}};

handle_info({post, Event}, #{token := Token, clients := Clients, events := Events} = State) ->
	case queue:out(Events) of
		{empty, _} ->
			lager:debug("[handle_info] post; Token: ~p; Event: ~p; Clients: ~p", [Token, Event, Clients]),
			[Client ! {event, Event} || Client <- Clients],
			{noreply, State#{clients => []}};
		{{value, FrontEvent}, RestEvents} ->
			lager:debug("[handle_info] send front event to Clients; Token: ~p; Event: ~p; Clients: ~p", [Token, Event, Clients]),
			[Client ! {event, FrontEvent} || Client <- Clients],
			{noreply, State#{clients => [], events => queue:in(Event, RestEvents)}}
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