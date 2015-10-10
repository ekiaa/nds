-module(nds_publisher_manager).

-behaviour(gen_server).

%% API functions

-export([start_link/0, send/2]).

%% gen_server callbacks

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(TABLE, ?MODULE).

%-------------------------------------------------------------------------------

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

send(QueueName, Message) ->
	case ets:lookup(?TABLE, QueueName) of
		[] ->
			gen_server:cast(?MODULE, {create_publisher_and_send, QueueName, Message});
		[{_, Publisher}] ->
			Publisher ! Message, ok
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

handle_cast({create_publisher_and_send, QueueName, Message}, State) ->
	case ets:lookup(?TABLE, QueueName) of
		[] ->
			case nds_publisher:start(QueueName) of
				{ok, Publisher} ->
					ets:insert(?TABLE, [{QueueName, Publisher}, {Publisher, QueueName}]),
					erlang:monitor(process, Publisher),
					Publisher ! Message,
					{noreply, State};
				Result ->
					lager:error("[handle_cast] Publisher start error: ~p; QueueName: ~p; Message: ~p", [Result, QueueName, Message]),
					{noreply, State}
			end;
		[{_, Publisher}] ->
			Publisher ! Message,
			{noreply, State}
	end;

handle_cast(Message, State) ->
	lager:error("[handle_cast] Message: ~p", [Message]),
	{stop, {error, {?MODULE, ?LINE, Message}}, State}.

%-------------------------------------------------------------------------------

handle_info({'DOWN', _, _, Publisher, Reason}, State) ->
	case ets:lookup(?TABLE, Publisher) of
		[] ->
			lager:error("[handle_info] 'DOWN' not matched Publisher: ~p; Reason: ~p", [Publisher, Reason]),
			{noreply, State};
		[{_, QueueName}] ->
			ets:delete(?TABLE, QueueName),
			ets:delete(?TABLE, Publisher),
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