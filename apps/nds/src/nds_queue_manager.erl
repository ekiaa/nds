-module(nds_queue_manager).

-behaviour(gen_server).

%% API functions

-export([start_link/0, get_queue/1]).

%% gen_server callbacks

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(TABLE, nds_queue_db).

%-------------------------------------------------------------------------------

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

get_queue(Token) ->
	case ets:lookup(?TABLE, Token) of
		[] ->
			gen_server:call(?MODULE, {create_queue, Token});
		[{Token, Queue}] ->
			Queue
	end.

%-------------------------------------------------------------------------------

init([]) ->
	ets:new(?TABLE, [named_table, protected, {read_concurrency, true}]),
	lager:debug("[init] ets table ~p created", [?TABLE]),
	{ok, #{tokens => #{}}};

init(Args) ->
	lager:error("[init] Args: ~p", [Args]),
	{stop, {error, {?MODULE, ?LINE, Args}}}.

%-------------------------------------------------------------------------------

handle_call({create_queue, Token}, _, #{tokens := Tokens} = State) ->
	{ok, Queue} = nds_queue:start(Token),
	ets:insert(?TABLE, {Token, Queue}),
	monitor(process, Queue),
	{reply, Queue, State#{tokens => maps:put(Queue, Token, Tokens)}};

handle_call(Request, From, State) ->
	lager:error("[handle_call] From: ~p; Request: ~p", [From, Request]),
	Error = {error, {?MODULE, ?LINE, {From, Request}}},
	{stop, Error, Error, State}.

%-------------------------------------------------------------------------------

handle_cast(Message, State) ->
	lager:error("[handle_cast] Message: ~p", [Message]),
	{stop, {error, {?MODULE, ?LINE, Message}}, State}.

%-------------------------------------------------------------------------------

handle_info({'DOWN', _, _, Queue, Reason}, #{tokens := Tokens} = State) ->
	case maps:get(Queue, Tokens, undefined) of
		undefined ->
			lager:debug("[handle_info] not matched Process ~p down with ~p", [Queue, Reason]),
			{noreply, State};
		Token ->
			lager:debug("[handle_info] Queue ~p down with ~p", [Queue, Reason]),
			ets:delete(?TABLE, Token),
			{noreply, State#{tokens => maps:remove(Queue, Tokens)}}
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