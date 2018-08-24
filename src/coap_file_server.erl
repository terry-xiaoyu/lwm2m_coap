-module(coap_file_server).
-export([start/0]).

-behaviour(coap_resource).

-export([coap_discover/2, coap_get/5, coap_post/4, coap_put/4, coap_delete/3,
    coap_observe/4, coap_unobserve/1, handle_info/2, coap_ack/2]).

-include("coap.hrl").

-define(APP, ?MODULE).

% resource operations
coap_discover(Prefix, _Args) ->
    io:format("discover ~p~n", [Prefix]),
    [{absolute, Prefix++Name, []} || Name <- mnesia:dirty_all_keys(resources)].

%% TODO: create an independent coap_file_server project,
%%   and support configs from system envirment variables.
coap_get(_ChId, _Prefix = [<<"file">>], _Query,
        #coap_content{uri_path=UriPath, uri_query=UriQuery, block2=Block2}, State) ->
    io:format("GET - ChId:~p, UriPath:~p, UriQuery:~p, Block2: ~p~n",
        [_ChId, UriPath, UriQuery, Block2]),

    %% TODO:
    %% Cache the file into a ets table.
    %%  divive the file into many small blocks and store each block into ets
    %%  with their Block Num as Key.
    try
        {ok, Filename} = filename(UriQuery),
        FullFilePath = filename:join(code:priv_dir(?APP), Filename),
        error_logger:info_msg("got file path: ~p", [FullFilePath]),

        {ok, Bytes} = file:read_file(FullFilePath),
        {ok, #coap_content{payload = Bytes}, State}
    catch
        error:{badmatch,{error, bad_filename}} ->
            error_logger:error_msg("incorrect file param: ~p, stacktrace:~p~n",
                [UriQuery, erlang:get_stacktrace()]),
            {error, bad_request, State};
        error:{badmatch,{error,enoent}} ->
            error_logger:error_msg("file not found, param: ~p, stacktrace:~p~n",
                [UriQuery, erlang:get_stacktrace()]),
            {error, bad_request, State};
        _Ex:_Err ->
            error_logger:error_msg("~p,~p, stacktrace:~p~n",
                [_Ex, _Err, erlang:get_stacktrace()]),
            {error, internal_server_error, State}
    end.

coap_post(_ChId, _Prefix, [<<"stop">>], _Content) ->
    main ! stop,
    {ok, content, #coap_content{}};
coap_post(_ChId, Prefix, Path, Content) ->
    io:format("post ~p ~p ~p~n", [Prefix, Path, Content]),
    {error, method_not_allowed}.

coap_put(_ChId, Prefix, Path, Content) ->
    io:format("put ~p ~p ~p~n", [Prefix, Path, Content]),
    coap_responder:notify(Prefix++Path, Content),
    ok.

coap_delete(_ChId, Prefix, Path) ->
    io:format("delete ~p ~p~n", [Prefix, Path]),
    coap_responder:notify(Prefix++Path, {error, not_found}),
    ok.

coap_observe(_ChId, Prefix, Path, _Ack) ->
    io:format("observe ~p ~p~n", [Prefix, Path]),
    {ok, {state, Prefix, Path}}.

coap_unobserve({state, Prefix, Path}) ->
    io:format("unobserve ~p ~p~n", [Prefix, Path]),
    ok.

handle_info(_Message, State) -> {noreply, State}.
coap_ack(_Ref, State) -> {ok, State}.

start() ->
    register(main, self()),

    {ok, _} = application:ensure_all_started(lwm2m_coap),
    ResourceHandlers = [
        {[<<"file">>], ?MODULE, undefined}
    ],
    lwm2m_coap_server:start_registry(ResourceHandlers),

    Port = application:get_env(?APP, port, 5683),
    Opts = application:get_env(?APP, options, []),
    lwm2m_coap_server:start_udp(udp_socket, Port, Opts),

    CertFile = application:get_env(?APP, certfile, ""),
    KeyFile = application:get_env(?APP, keyfile, ""),
    case (filelib:is_regular(CertFile) andalso filelib:is_regular(KeyFile)) of
        true ->
            lwm2m_coap_server:start_dtls(dtls_socket, Port+1, [{certfile, CertFile}, {keyfile, KeyFile}]);
        false ->
            error_logger:info_msg("certfile ~p or keyfile ~p are not valid, turn off coap DTLS", [CertFile, KeyFile])
    end.

%% internal functions

filename(QueryList) ->
    lists:foldl(fun
            (_Query = <<"name=", Filename/binary>>, _Acc) -> {ok, Filename};
            (_Query, Acc) -> Acc
        end, {error, bad_filename}, QueryList).
% end of file
