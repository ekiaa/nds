-module(nds_http_handler).

-export([init/3, handle/2, info/3, terminate/3]).

init({tcp, http}, Req, _Opts) ->
	get_method(Req, #{});
init(_Type, Req, _Opts) ->
	{shutdown, Req, no_state}.	

get_method({Method, Req}, State) ->
	get_queue_name(Req, State#{method => Method});
get_method(Req, State) ->
	get_method(cowboy_req:method(Req), State).

get_queue_name({QueueName, Req}, State) ->
	processing(Req, State#{queue_name => QueueName});
get_queue_name(Req, State) ->
	get_queue_name(cowboy_req:binding(queue_name, Req), State).

processing(Req, #{method := <<"GET">>} = State) ->
	get_subscriber_name(Req, State#{type => subscriber});
processing(Req, #{method := <<"POST">>} = State) ->
	get_body(Req, State#{type => publisher});
processing(Req, State) ->
	reply_not_found(Req, State).

get_subscriber_name({SubscriberName, Req}, State) ->
	get_message(Req, State#{subscriber_name => SubscriberName});
get_subscriber_name(Req, State) ->
	get_subscriber_name(cowboy_req:binding(subscriber_name, Req), State).

get_message(Req, #{subscriber_name := SubscriberName, queue_name := QueueName} = State) ->
	nds_subscriber:get(SubscriberName, QueueName),
	Timeout = application:get_env(nds, timeout, 30000),
	{loop, Req, State#{reply_message => false}}.
	% {loop, Req, State#{reply_message => false}, Timeout, hibernate}.

get_body({ok, Message, Req}, State) ->
	post_message(Message, Req, State);
get_body(Req, State) ->
	get_body(cowboy_req:body(Req), State).

post_message(Message, Req, #{queue_name := QueueName} = State) ->
	nds_publisher:post(QueueName, Message),
	reply_ok(Req, State).

handle(Req, State) ->
	{ok, Req, State}.

info({message, Message}, Req, #{type := subscriber} = State) when is_binary(Message) ->
	reply_message(Message, Req, State);
info(Info, Req, State) ->
	lager:error("[info] not matched Info: ~p; State: ~p", [Info, State]),
	reply_not_found(Req, State).

reply_ok(Req, State) ->
	reply(cowboy_req:reply(200, Req), State).

reply_message(Message, Req, State) ->
	reply(cowboy_req:reply(200, [], Message, Req), State#{reply_message => true}).

reply_not_found(Req, State) ->
	reply(cowboy_req:reply(404, [], <<"Not Found">>, Req), State).

reply({ok, Req}, State) ->
	{ok, Req, State}.

terminate(_Reason, _Req, #{subscriber_name := SubscriberName, queue_name := QueueName}) ->
	nds_subscriber:cancel(SubscriberName, QueueName),
	ok;
terminate(_Reason, _Req, _State) ->
	ok.