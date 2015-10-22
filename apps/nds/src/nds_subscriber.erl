-module(nds_subscriber).

-behaviour(gen_server).

%% API functions

-export([start/2, start_link/2, get/2, cancel/2, publish/2]).

%% gen_server States

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(MSG_QUEUE_LIMIT, 10).

%-------------------------------------------------------------------------------

start(SubscriberName, QueueName) ->
	nds_subscriber_sup:start_child([SubscriberName, QueueName]).

start_link(SubscriberName, QueueName) ->
	gen_server:start_link(?MODULE, #{subscriber_name => SubscriberName, queue_name => QueueName}, []).

get(SubscriberName, QueueName) ->
	nds_subscriber_manager:send(SubscriberName, QueueName, {get, self()}).

cancel(SubscriberName, QueueName) ->
	nds_subscriber_manager:send(SubscriberName, QueueName, {cancel, self()}).

publish(Subscriber, Message) ->
	gen_server:cast(Subscriber, {publish, Message}).

%-------------------------------------------------------------------------------

init(#{queue_name := QueueName} = State) ->
	nds_manager:increment(),
	nds_publisher:subscribe(QueueName),
	timer:send_interval(30000, check_timestamp),
	QueueLimit = application:get_env(nds, queue_limit, ?MSG_QUEUE_LIMIT),
	{ok, State#{clients => [], messages => queue:new(), timestamp => erlang:now(), queue_limit => QueueLimit}};

init(Args) ->
	lager:error("[init] Args: ~p", [Args]),
	{stop, {error, {?MODULE, ?LINE, Args}}}.

%-------------------------------------------------------------------------------

handle_call(Request, From, State) ->
	lager:error("[handle_call] From: ~p; Request: ~p", [From, Request]),
	Error = {error, {?MODULE, ?LINE, {From, Request}}},
	{stop, Error, Error, State}.

%-------------------------------------------------------------------------------

handle_cast({publish, Message}, #{clients := [], messages := Messages, queue_limit := QueueLimit} = State) ->
	case queue:len(Messages) of
		QueueLimit ->
			% lager:warning("[handle_cast] publish Message; Messages len >= ~p", [?MSG_QUEUE_LIMIT]),
			{{value, FrontMessage}, RestMessages} = queue:out(Messages),
			{noreply, State#{messages => queue:in(Message, RestMessages)}};
		_ ->
			{noreply, State#{messages => queue:in(Message, Messages)}}
	end;

handle_cast({publish, Message}, #{clients := Clients, messages := Messages} = State) ->
	% queue:is_empty(Messages) orelse lager:warning("[handle_call] publish Message; Messages not empty!!!"),	
	[Client ! {message, Message} || Client <- Clients],
	{noreply, State#{clients => [], timestamp => erlang:now()}};

handle_cast(Message, State) ->
	lager:error("[handle_cast] Message: ~p", [Message]),
	{stop, {error, {?MODULE, ?LINE, Message}}, State}.

%-------------------------------------------------------------------------------

handle_info({get, NewClient}, #{clients := Clients, messages := Messages} = State) ->
	case queue:out(Messages) of
		{empty, _} ->
			{noreply, State#{clients => [NewClient | Clients], timestamp => erlang:now()}};
		{{value, FrontMessage}, RestMessages} ->
			[Client ! {message, FrontMessage} || Client <- [NewClient | Clients]],
			{noreply, State#{clients => [], messages => RestMessages, timestamp => erlang:now()}}
	end;

handle_info({cancel, Client}, #{clients := Clients} = State) ->
	{noreply, State#{clients => lists:delete(Client, Clients)}};

handle_info(check_timestamp, #{clients := [], timestamp := Timestamp} = State) ->
	case timer:now_diff(now(), Timestamp) of
		Tdiff when Tdiff > 120000000 ->
			{stop, normal, State};
		_ ->
			{noreply, State}
	end;

handle_info(check_timestamp, State) ->
	{noreply, State};

handle_info(Info, State) ->
	lager:error("[handle_info] Info: ~p", [Info]),
	{stop, {error, {?MODULE, ?LINE, Info}}, State}.

%-------------------------------------------------------------------------------

terminate(Reason, State) -> 
	nds_manager:decrement(),
	case Reason of
		normal -> ok;
		_ -> lager:error("[terminate] Reason: ~p; State: ~p", [Reason, State]), ok
	end.

%-------------------------------------------------------------------------------

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.