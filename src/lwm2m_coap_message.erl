%
% The contents of this file are subject to the Mozilla Public License
% Version 1.1 (the "License"); you may not use this file except in
% compliance with the License. You may obtain a copy of the License at
% http://www.mozilla.org/MPL/
%
% Copyright (c) 2015 Petr Gotthard <petr.gotthard@centrum.cz>
%

% convenience functions for message construction
-module(lwm2m_coap_message).

-export([request/2, request/3, request/4, ack/1, response/1, response/2, response/3]).
-export([set/3, set_payload/2, get_content/1, set_content/2, set_content/3]).

-include("coap.hrl").

request(Type, Method) ->
    request(Type, Method, <<>>, []).

request(Type, Method, Payload) ->
    request(Type, Method, Payload, []).

request(Type, Method, Payload, Options) when is_binary(Payload) ->
    #coap_message{type=Type, method=Method, payload=Payload, options=Options};
request(Type, Method, Content=#coap_content{}, Options) ->
    set_content(Content,
        #coap_message{type=Type, method=Method, options=Options}).


ack(Request=#coap_message{}) ->
    #coap_message{
        type=ack,
        id=Request#coap_message.id
    }.

response(Request=#coap_message{type=non}) ->
    #coap_message{
        type=non,
        token=Request#coap_message.token
    };
response(Request=#coap_message{type=con}) ->
    #coap_message{
        type=con,
        id=Request#coap_message.id,
        token=Request#coap_message.token
    }.

response(Method, Request) ->
    set_method(Method,
        response(Request)).

response(Method, Payload, Request) ->
    set_method(Method,
        set_payload(Payload,
            response(Request))).

% omit option for its default value
set(max_age, ?DEFAULT_MAX_AGE, Msg) -> Msg;
set(etag, ETag, Msg=#coap_message{options=Options}) ->
    Msg#coap_message{
        options=[{etag, [ETag]}|Options]
    };
% omit option for empty value
set(_Option, undefined, Msg) -> Msg;
% set non-default value
set(Option, Value, Msg=#coap_message{options=Options}) ->
    Msg#coap_message{
        options=[{Option, Value}|Options]
    }.

set_method(Method, Msg) ->
    Msg#coap_message{
        method=Method
    }.

set_payload(Payload=#coap_content{}, Msg) ->
    set_content(Payload, undefined, Msg);
set_payload(Payload, Msg) when is_binary(Payload) ->
    Msg#coap_message{
        payload=Payload
    };
set_payload(Payload, Msg) when is_list(Payload) ->
    Msg#coap_message{
        payload=list_to_binary(Payload)
    }.

get_content(#coap_message{options=Options, payload=Payload}) ->
    WithOpts = populate_content(Options),
    WithOpts#coap_content{payload = Payload}.

populate_content(Options) ->
    ContentFields = lists:foldr(
        fun(etag, Acc) ->
                ETagVar = case proplists:get_value(etag, Options) of
                            [ETag] -> ETag;
                            _Other -> undefined
                          end,
                [ETagVar | Acc];
            (max_age, Acc) ->
                [proplists:get_value(max_age, Options, ?DEFAULT_MAX_AGE) | Acc];
            (Key, Acc) ->
                [proplists:get_value(Key, Options) | Acc]
        end, [], record_info(fields, coap_content)),
    list_to_tuple([coap_content | ContentFields]).

set_content(Content, Msg) ->
    set_content(Content, undefined, Msg).

% segmentation not requested and not required
set_content(#coap_content{payload=Payload} = Content, undefined, Msg)
        when byte_size(Payload) =< ?MAX_BLOCK_SIZE ->
    WithPayload = set_payload(Payload, Msg),
    lists:foldr(
        fun(Key, Acc) ->
            set(Key, get_content_value(Key, Content), Acc)
        end, WithPayload, record_info(fields, coap_content) -- [payload]);
% segmentation not requested, but required (late negotiation)
set_content(Content, undefined, Msg) ->
    set_content(Content, {0, true, ?MAX_BLOCK_SIZE}, Msg);
% segmentation requested (early negotiation)
set_content(#coap_content{payload=Payload} = Content, Block, Msg) ->
    WithPayload = set_payload_block(Payload, Block, Msg),
    lists:foldr(
        fun(Key, Msg) ->
            set(Key, get_content_value(Key, Content), Msg)
        end, WithPayload, record_info(fields, coap_content) -- [payload]).

set_payload_block(Content, Block, Msg=#coap_message{method=Method}) when is_atom(Method) ->
    set_payload_block(Content, block1, Block, Msg);
set_payload_block(Content, Block, Msg=#coap_message{}) ->
    set_payload_block(Content, block2, Block, Msg).

set_payload_block(Content, BlockId, {Num, _, Size}, Msg) when byte_size(Content) > (Num+1)*Size ->
    set(BlockId, {Num, true, Size},
        set_payload(binary:part(Content, Num*Size, Size), Msg));
set_payload_block(Content, BlockId, {Num, _, Size}, Msg) ->
    set(BlockId, {Num, false, Size},
        set_payload(binary:part(Content, Num*Size, byte_size(Content)-Num*Size), Msg)).

get_content_value(etag, Content) -> Content#coap_content.etag;
get_content_value(max_age, Content) -> Content#coap_content.max_age;
get_content_value(content_format, Content) -> Content#coap_content.content_format;
get_content_value(uri_host, Content) -> Content#coap_content.uri_host;
get_content_value(uri_port, Content) -> Content#coap_content.uri_port;
get_content_value(uri_query, Content) -> Content#coap_content.uri_query;
get_content_value(uri_path, Content) -> Content#coap_content.uri_path;
get_content_value(location_path, Content) -> Content#coap_content.location_path;
get_content_value(location_query, Content) -> Content#coap_content.location_query;
get_content_value(if_match, Content) -> Content#coap_content.if_match;
get_content_value(if_none_match, Content) -> Content#coap_content.if_none_match;
get_content_value(accept, Content) -> Content#coap_content.accept;
get_content_value(proxy_uri, Content) -> Content#coap_content.proxy_uri;
get_content_value(proxy_scheme, Content) -> Content#coap_content.proxy_scheme;
get_content_value(size1, Content) -> Content#coap_content.size1;
get_content_value(observe, Content) -> Content#coap_content.observe;
get_content_value(block1, Content) -> Content#coap_content.block1;
get_content_value(block2, Content) -> Content#coap_content.block2;
get_content_value(payload, Content) -> Content#coap_content.payload.

% end of file
