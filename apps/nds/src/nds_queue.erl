-module(nds_queue).

-behaviour(gen_server).

%% API functions

-export([start/1, start_link/1, subscribe/1, publish/2]).

%% gen_server States

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%-------------------------------------------------------------------------------

start(Token) ->
	nds_queue_sup:start_child([Token]).

start_link(Token) ->
	gen_server:start_link(?MODULE, {token, Token}, []).

subscribe(Token) ->
	% lager:debug("[subscribe] Token: ~p", [Token]),
	Queue = nds_queue_manager:get_queue(Token),
	gen_server:cast(Queue, {subscribe, self()}).

publish(Token, Message) ->
	% lager:debug("[publish] Token: ~p; Message: ~p", [Token, Message]),
	Queue = nds_queue_manager:get_queue(Token),
	gen_server:cast(Queue, {publish, Message}).

%-------------------------------------------------------------------------------

init({token, Token}) ->
	% lager:debug("~p => init", [Token]),
	{ok, #{token => Token, subscribers => []}};

init(Args) ->
	lager:error("[init] Args: ~p", [Args]),
	{stop, {error, {?MODULE, ?LINE, Args}}}.

%-------------------------------------------------------------------------------

handle_call(Request, From, State) ->
	% lager:error("[handle_call] From: ~p; Request: ~p", [From, Request]),
	Error = {error, {?MODULE, ?LINE, {From, Request}}},
	{stop, Error, Error, State}.

%-------------------------------------------------------------------------------

handle_cast({subscribe, Subscriber}, #{token := Token, subscribers := Subscribers} = State) ->
	% lager:debug("~p => subscribe -> ~p; Subscribers: ~p", [Token, Subscriber, Subscribers]),
	monitor(process, Subscriber),
	{noreply, State#{subscribers => [Subscriber | Subscribers]}};

handle_cast({publish, Message}, #{token := Token, subscribers := []} = State) ->
	% lager:debug("~p => publish -> no subscribers; Message: ~p", [Token, Message]),
	{noreply, State};

handle_cast({publish, Message}, #{token := Token, subscribers := Subscribers} = State) ->
	% lager:debug("~p => publish -> ~p; Message: ~p", [Token, Subscribers, Message]),
	[Subscriber ! {publish, Message} || Subscriber <- Subscribers],
	{noreply, State};

handle_cast(Message, State) ->
	lager:error("[handle_cast] Message: ~p", [Message]),
	{stop, {error, {?MODULE, ?LINE, Message}}, State}.

%-------------------------------------------------------------------------------

handle_info({'DOWN', _, _, Subscriber, Reason}, #{token := Token, subscribers := Subscribers} = State) ->
	% lager:debug("~p => down -> ~p; Reason: ~p", [Token, Subscriber, Reason]),
	{noreply, State#{subscribers => lists:delete(Subscriber, Subscribers)}};

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