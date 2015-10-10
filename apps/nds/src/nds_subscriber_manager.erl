-module(nds_subscriber_manager).

-behaviour(gen_server).

%% API functions

-export([start_link/0, send/3]).

%% gen_server callbacks

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(TABLE, ?MODULE).

%-------------------------------------------------------------------------------

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

send(SubscriberName, QueueName, Message) ->
	case ets:lookup(?TABLE, {SubscriberName, QueueName}) of
		[] ->
			gen_server:cast(?MODULE, {create_subscriber_and_send, SubscriberName, QueueName, Message});
		[{_, Subscriber}] ->
			Subscriber ! Message, ok
	end.

%-------------------------------------------------------------------------------

init([]) ->
	ets:new(?TABLE, [named_table, protected, {read_concurrency, true}]),
	{ok, #{}};

init(Args) ->
	lager:error("[init] Args: ~p", [Args]),
	{stop, {error, {?MODULE, ?LINE, Args}}}.

%-------------------------------------------------------------------------------

handle_call(Request, From, State) ->
	lager:error("[handle_call] From: ~p; Request: ~p", [From, Request]),
	Error = {error, {?MODULE, ?LINE, {From, Request}}},
	{stop, Error, Error, State}.

%-------------------------------------------------------------------------------

handle_cast({create_subscriber_and_send, SubscriberName, QueueName, Message}, State) ->
	case ets:lookup(?TABLE, {SubscriberName, QueueName}) of
		[] ->
			case nds_subscriber:start(SubscriberName, QueueName) of
				{ok, Subscriber} ->
					erlang:monitor(process, Subscriber),
					ets:insert(?TABLE, [{{SubscriberName, QueueName}, Subscriber}, {Subscriber, {SubscriberName, QueueName}}]),
					Subscriber ! Message,
					{noreply, State};
				Result ->
					lager:error("[handle_call] Subscriber start error: ~p; SubscriberName: ~p; QueueName: ~p; Message: ~p", [Result, SubscriberName, QueueName, Message]),
					{noreply, State}
			end;
		[{_, Subscriber}] ->
			Subscriber ! Message,
			{noreply, State}
	end;

handle_cast(Message, State) ->
	lager:error("[handle_cast] Message: ~p", [Message]),
	{stop, {error, {?MODULE, ?LINE, Message}}, State}.

%-------------------------------------------------------------------------------

handle_info({'DOWN', _, _, Subscriber, Reason}, State) ->
	case ets:lookup(?TABLE, Subscriber) of
		[] ->
			lager:error("[handle_info] 'DOWN' not matched Subscriber: ~p; Reason: ~p", [Subscriber, Reason]),
			{noreply, State};
		[{_, Key}] ->
			ets:delete(?TABLE, Key),
			ets:delete(?TABLE, Subscriber),
			{noreply, State}
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