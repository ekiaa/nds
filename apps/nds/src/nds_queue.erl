-module(nds_queue).

-behaviour(gen_server).

%% API functions

-export([start/1, start_link/1, subscribe/1, unsubscribe/1, publish/2]).

%% gen_server States

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%-------------------------------------------------------------------------------

start(Token) ->
	nds_queue_sup:start_child([Token]).

start_link(Token) ->
	gen_server:start_link(?MODULE, {token, Token}, []).

subscribe(Token) ->
	lager:debug("[subscribe] Token: ~p", [Token]),
	case catch gproc:lookup_local_name({?MODULE, Token}) of
		Pid when is_pid(Pid) ->
			gen_server:cast(Pid, {subscribe, self()});
		Result1 ->
			lager:debug("[subscribe] gproc:lookup_local_name() return: ~p", [Result1]),
			case catch ?MODULE:start(Token) of
				{ok, Pid} ->
					gen_server:cast(Pid, {subscribe, self()});
				Result2 ->
					lager:debug("[subscribe] start(Token) return: ~p; Token: ~p", [Result2, Token]),
					Result2
			end
	end.

unsubscribe(Token) ->
	Subscriber = self(),
	lager:debug("[unsubscribe] Token: ~p; Subscriber: ~p", [Token, Subscriber]),
	case catch gproc:send({n, l, {?MODULE, Token}}, {unsubscribe, Subscriber}) of
		Result -> lager:debug("[unsubscribe] gproc:send(Key, Message) return: ~p", [Result]), ok
	end.

publish(Token, Event) ->
	lager:debug("[publish] Token: ~p; Event: ~p", [Token, Event]),
	case catch gproc:lookup_local_name({?MODULE, Token}) of
		_Pid when is_pid(_Pid) ->
			publish_event(Token, Event);
		Result1 ->
			lager:debug("[publish] gproc:lookup_local_name() return: ~p", [Result1]),
			case catch ?MODULE:start(Token) of
				{ok, _Pid} ->
					publish_event(Token, Event);
				Result2 ->
					lager:debug("[publish] Token: ~p; start(Token) return: ~p", [Token, Result2]),
					Result2
			end
	end.

publish_event(Token, Event) ->
	Nodes = [node() | nodes()],
	case catch gproc:bcast(Nodes, {n, l, {?MODULE, Token}}, {publish, Event}) of
		Result -> lager:debug("[publish_event] Token: ~p; Event: ~p; gproc:bcast(Nodes) return: ~p; Nodes: ~p", [Token, Event, Result, Nodes]), ok
	end.

%-------------------------------------------------------------------------------

init({token, Token}) ->
	lager:debug("[init] Token: ~p", [Token]),
	case catch gproc:add_local_name({?MODULE, Token}) of
		true ->
			lager:debug("[init] started"),
			{ok, #{token => Token, subscribers => []}};
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

handle_cast({subscribe, Subscriber}, #{token := Token, subscribers := Subscribers} = State) ->
	lager:debug("[handle_cast] subscribe; Token: ~p; Subscriber: ~p; Subscribers: ~p", [Token, Subscriber, Subscribers]),
	{noreply, State#{subscribers => [Subscriber | Subscribers]}};

handle_cast(Message, State) ->
	lager:error("[handle_cast] Message: ~p", [Message]),
	{stop, {error, {?MODULE, ?LINE, Message}}, State}.

%-------------------------------------------------------------------------------

handle_info({unsubscribe, Subscriber}, #{token := Token, subscribers := Subscribers} = State) ->
	lager:debug("[handle_info] unsubscribe; Token: ~p; Subscriber: ~p", [Token, Subscriber]),
	{noreply, State#{subscribers => lists:delete(Subscriber, Subscribers)}};

handle_info({publish, Event}, #{token := Token, subscribers := []} = State) ->
	lager:debug("[handle_info] publish; Token: ~p; Subscribers: []; Event: ~p", [Token, Event]),
	{noreply, State};

handle_info({publish, Event}, #{token := Token, subscribers := Subscribers} = State) ->
	lager:debug("[handle_info] publish; Token: ~p; Subscribers: ~p; Event: ~p", [Token, Subscribers, Event]),
	[Subscriber ! {event, Event} || Subscriber <- Subscribers],
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