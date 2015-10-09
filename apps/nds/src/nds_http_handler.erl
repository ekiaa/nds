-module(nds_http_handler).

-export([init/2, info/3, terminate/3]).

init(Req, Opts) ->
	case {cowboy_req:method(Req), cowboy_req:binding(token, Req)} of
		{<<"GET">>, <<"favicon.ico">>} ->
			cowboy_req:reply(404, Req),
			{ok, Req, Opts};
		{<<"GET">>, Token} ->
			% lager:debug("[init] GET; Token: ~p", [Token]),
			Connection = cowboy_req:binding(connection, Req),
			nds_connection:get(Connection, Token),
			Timeout = application:get_env(nds, timeout, 30000),
			{cowboy_loop, Req, #{token => Token, connection => Connection, send_event => false}, Timeout, hibernate};
		{<<"POST">>, Token} ->
			{ok, Message, Req_1} = cowboy_req:body(Req),
			% lager:debug("[init] POST; Token: ~p; Message: ~p", [Token, Message]),
			nds_queue:publish(Token, Message),
			{ok, cowboy_req:reply(200, [], <<>>, Req_1), #{token => Token, connection => undefined, send_event => undefined}};
		_Request ->
			lager:error("[init] nomatch request: ~p", [_Request]),
			cowboy_req:reply(404, Req),
			{ok, Req, Opts}
	end.

info({message, Message}, Req, #{token := Token} = State) when is_binary(Message) ->
	% lager:debug("[info] Token: ~p; Message: ~p", [Token, Message]),
	{shutdown, cowboy_req:reply(200, [], Message, Req), State#{send_event => true}};

info(Info, Req, State) ->
	lager:error("[info] nomatch Info: ~p", [Info]),
	{ok, Req, State}.

terminate(normal, _Req, #{send_event := false, connection := Connection, token := Token}) ->
	nds_connection:close(Connection, Token),
	ok;
terminate(Reason, _Req, #{send_event := false, connection := Connection, token := Token}) ->
	% lager:debug("[terminate] send_event: false; Connection: ~p; Token:~p; Reason: ~p", [Connection, Token, Reason]),
	nds_connection:close(Connection, Token),
	ok;
terminate(normal, _Req, _State) ->
	ok;
terminate(shutdown, _Req, _State) ->
	ok;
terminate(Reason, _Req, State) ->
	lager:debug("[terminate] Reason: ~p; State: ~p", [Reason, State]),
	ok.