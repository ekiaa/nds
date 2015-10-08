-module(nds_http_handler).

-export([init/2, info/3, terminate/3]).

init(Req, Opts) ->
	% try
		case {cowboy_req:method(Req), cowboy_req:binding(token, Req)} of
			{<<"GET">>, <<"favicon.ico">>} ->
				cowboy_req:reply(404, Req),
				{ok, Req, Opts};
			{<<"GET">>, Token} ->
				lager:debug("[init] GET; Token: ~p", [Token]),
				Connection = cowboy_req:binding(connection, Req),
				nds_connection:get(Connection, Token),
				{cowboy_loop, Req, Opts};
			{<<"POST">>, Token} ->
				{ok, Event, Req_1} = cowboy_req:body(Req),
				lager:debug("[init] POST; Token: ~p; Event: ~p", [Token, Event]),
				nds_queue:publish(Token, Event),
				{ok, cowboy_req:reply(200, [], <<>>, Req_1), Opts};
			_Request ->
				lager:error("[init] nomatch request: ~p", [_Request]),
				cowboy_req:reply(404, Req),
				{ok, Req, Opts}
		end
	% catch
	% 	T:R ->
	% 		lager:error("[init] ~p; Req: ~p", [{T,R}, Req]),
	% 		cowboy_req:reply(500, Req),
	% 		{ok, Req, Opts}
	% end
	.

info({event, Event}, Req, State) when is_binary(Event) ->
	Token = cowboy_req:binding(token, Req),
	lager:debug("[info] Token: ~p; Event: ~p", [Token, Event]),
	{shutdown, cowboy_req:reply(200, [], Event, Req), State};

info(Info, Req, State) ->
	lager:debug("[info] nomatch Info: ~p", [Info]),
	{ok, Req, State}.

terminate(normal, _Req, _State) ->
	ok;
terminate(shutdown, _Req, _State) ->
	ok;
terminate(_Reason, _Req, _State) ->
	lager:debug("[terminate] Reason: ~p", [_Reason]),
	ok.
