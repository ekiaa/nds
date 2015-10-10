-module(nds_http_handler).

-export([init/3, handle/2, info/3, terminate/3]).

init({tcp, http}, Req, _Opts) ->
	% lager:debug("[init] {tcp, http} => ok"),
	get_method(cowboy_req:method(Req), #{});

init(_Type, Req, _Opts) ->
	% lager:debug("[init] ~p => shutdown"),
	{shutdown, Req, no_state}.	

get_method({Method, Req}, State) ->
	% lager:debug("[get_method] Method: ~p", [Method]),
	get_token(cowboy_req:binding(token, Req), State#{method => Method}).

get_token({Token, Req}, State) ->
	% lager:debug("[get_token] Token: ~p", [Token]),
	get_connection(cowboy_req:binding(connection, Req), State#{token => Token}).

get_connection({Connection, Req}, State) ->
	% lager:debug("[get_connection] Connection: ~p", [Connection]),
	processing(Req, State#{connection => Connection}).

processing(Req, #{method := <<"GET">>, token := <<"favicon.ico">>} = State) ->
	send_not_found(Req, State);

processing(Req, #{method := <<"GET">>, token := Token, connection := Connection} = State) when is_binary(Token) ->
	% lager:debug("[processing] subscriber"),
	nds_connection:get(Connection, Token),
	Timeout = application:get_env(nds, timeout, 30000),
	{loop, Req, State#{type => subscriber, recv_msg => false}, Timeout, hibernate};

processing(Req, #{method := <<"POST">>, token := Token} = State) when is_binary(Token) ->
	% lager:debug("[processing] publisher"),
	get_message(cowboy_req:body(Req), State);

processing(Req, State) ->
	send_not_found(Req, State).

get_message({ok, Message, Req}, #{token := Token} = State) ->
	% lager:debug("[get_message] Message: ~p", [Message]),
	nds_queue:publish(Token, Message),
	{ok, Req, State#{type => publisher}}.

handle(Req, State) ->
	% lager:debug("[handle]"),
	{ok, Req, State}.

info({message, Message}, Req, #{type := subscriber, token := Token, connection := Connection} = State) when is_binary(Message) ->
	% lager:debug("[info] Token: ~p; Connection: ~p; Message: ~p", [Token, Connection, Message]),
	send_message_to_subscriber(Message, Req, State);

info(Info, Req, State) ->
	% lager:error("[info] nomatch Info: ~p", [Info]),
	{loop, Req, State, hibernate}.

send_message_to_subscriber(Message, Req, State) ->
	send_response(cowboy_req:reply(200, [], Message, Req), State#{recv_msg := true}).

send_not_found(Req, State) ->
	send_response(cowboy_req:reply(404, [], <<"Not Found">>, Req), State).

send_response({ok, Req}, State) ->
	% lager:debug("[send_response] ok"),
	{ok, Req, State}.

% terminate(normal, _Req, #{recv_msg := false, connection := Connection, token := Token}) ->
% 	nds_connection:close(Connection, Token),
% 	ok;
terminate(Reason, _Req, #{recv_msg := false, connection := Connection, token := Token}) ->
	% lager:debug("[terminate] recv_msg: false; Connection: ~p; Token:~p; Reason: ~p", [Connection, Token, Reason]),
	nds_connection:close(Connection, Token),
	ok;
% terminate(normal, _Req, _State) ->
% 	ok;
% terminate(shutdown, _Req, _State) ->
% 	ok;
terminate(Reason, _Req, State) ->
	% lager:debug("[terminate] Reason: ~p; State: ~p", [Reason, State]),
	ok.