-module(nds_publisher).

-behaviour(gen_server).

%% API functions

-export([start/1, start_link/1, subscribe/1, post/2]).

%% gen_server States

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%-------------------------------------------------------------------------------

start(QueueName) ->
	nds_publisher_sup:start_child([QueueName]).

start_link(QueueName) ->
	gen_server:start_link(?MODULE, #{queue_name => QueueName}, []).

subscribe(QueueName) ->
	nds_publisher_manager:send(QueueName, {subscribe, self()}).

post(QueueName, Message) ->
	nds_publisher_manager:send(QueueName, {post, Message}).

%-------------------------------------------------------------------------------

init(#{} = State) ->
	{ok, State#{subscribers => []}};

init(Args) ->
	lager:error("[init] Args: ~p", [Args]),
	{stop, {error, {?MODULE, ?LINE, Args}}}.

%-------------------------------------------------------------------------------

handle_call(Request, From, State) ->
	lager:error("[handle_call] From: ~p; Request: ~p", [From, Request]),
	Error = {error, {?MODULE, ?LINE, {From, Request}}},
	{stop, Error, Error, State}.

%-------------------------------------------------------------------------------

handle_cast(Message, State) ->
	lager:error("[handle_cast] Message: ~p", [Message]),
	{stop, {error, {?MODULE, ?LINE, Message}}, State}.

%-------------------------------------------------------------------------------

handle_info({subscribe, Subscriber}, #{subscribers := Subscribers} = State) ->
	erlang:monitor(process, Subscriber),
	{noreply, State#{subscribers => [Subscriber | Subscribers]}};

handle_info({post, _Message}, #{subscribers := []} = State) ->
	{noreply, State};

handle_info({post, Message}, #{subscribers := Subscribers} = State) ->
	[nds_subscriber:publish(Subscriber, Message) || Subscriber <- Subscribers],
	{noreply, State};

handle_info({'DOWN', _, _, Subscriber, _Reason}, #{subscribers := Subscribers} = State) ->
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