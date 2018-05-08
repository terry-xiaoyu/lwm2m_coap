%
% The contents of this file are subject to the Mozilla Public License
% Version 1.1 (the "License"); you may not use this file except in
% compliance with the License. You may obtain a copy of the License at
% http://www.mozilla.org/MPL/
%
% Copyright (c) 2015 Petr Gotthard <petr.gotthard@centrum.cz>
%

-module(lwm2m_coap_responder_sup).
-behaviour(supervisor).

-export([start_link/0, get_responder/3, init/1]).

-include("coap.hrl").

start_link() ->
    supervisor:start_link(?MODULE, []).

get_responder(SupPid, ChId, Request) ->
    case start_responder(SupPid, ChId, Request) of
        {ok, Pid} -> {ok, Pid};
        {error, {already_started, Pid}} -> {ok, Pid};
        {error, Other} -> {error, Other}
    end.

start_responder(SupPid, ChId, #coap_message{options=Options}) ->
    Uri = proplists:get_value(uri_path, Options, []),
    supervisor:start_child(SupPid,
        {ChId,
            {lwm2m_coap_responder, start_link, [self(), Uri]},
            temporary, 5000, worker, []}).

init([]) ->
    {ok, {{one_for_one, 3, 10}, []}}.

% end of file
