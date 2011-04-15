-module(riak_rabbitmq).
-include_lib("amqp_client/include/amqp_client.hrl").

-export([
  postcommit_send_amqp/1
]).

-define(DELETED, <<"X-Riak-Deleted">>).
-define(META, <<"X-Riak-Meta">>).
-define(EXCHANGE, <<"X-Riak-Meta-AMQP-Exchange">>).
-define(ROUTING_KEY, <<"X-Riak-Meta-AMQP-Routing-Key">>).
-define(HOST, <<"X-Riak-Meta-AMQP-Host">>).
-define(PORT, <<"X-Riak-Meta-AMQP-Port">>).
-define(VHOST, <<"X-Riak-Meta-AMQP-VHost">>).
-define(USER, <<"X-Riak-Meta-AMQP-User">>).
-define(PASSWORD, <<"X-Riak-Meta-AMQP-Password">>).

-define(CONTENT_TYPE, <<"content-type">>).

postcommit_send_amqp(RObj) ->
                                                % io:format("robj: ~p~n", [RObj]),
  Metadata = riak_object:get_metadata(RObj),
                                                % io:format("metadata: ~p~n", [Metadata]),

  Exchange = key_find(?EXCHANGE, Metadata, riak_object:bucket(RObj)),
  RoutingKey = key_find(?ROUTING_KEY, Metadata, riak_object:key(RObj)),
  ContentType = list_to_binary(key_find(?CONTENT_TYPE, Metadata, "application/octet-stream")),
  Body = riak_object:get_value(RObj),

                                                % Publish a message
  Publish = #'basic.publish'{ exchange=Exchange, routing_key=RoutingKey },
  Headers = key_find(?META, Metadata, []),
  AppHdrs = lists:foldl(fun ({HdrKey, HdrValue}, NewHdrs) ->
                            <<_:12/binary, Key/binary>> = list_to_binary(HdrKey),
                            [{binary_to_list(Key), binary, HdrValue} | NewHdrs]
                        end, [], Headers),
  ExtraHdrs = [case key_find(?DELETED, Metadata, "false") of
                 "true" -> {"X-Riak-Deleted", binary, "true"};
                 "false" -> []
               end],
  Props = #'P_basic'{ content_type=ContentType, headers=lists:flatten([AppHdrs, ExtraHdrs]) },

  Msg = #amqp_msg{ payload=Body, props=Props },
                                                % io:format("message: ~p~n", [Msg]),
  {ok, Channel} = amqp_channel(RObj),
  amqp_channel:cast(Channel, Publish, Msg),

                                                %ObjJson = mochijson2:encode(riak_object:to_json(RObj)),
                                                % io:format("sent object: ~p~n", [ObjJson]),

  ok.

amqp_channel(RObj) ->
  AmqpParams = amqp_p(RObj),
  case pg2:get_closest_pid(AmqpParams) of
    {error, {no_such_group, _}} -> 
      pg2:create(AmqpParams),
      amqp_channel(RObj);
    {error, {no_process, _}} -> 
      case amqp_connection:start(network, AmqpParams) of
        {ok, Client} ->
                                                % io:format("started new client: ~p~n", [Client]),
          case amqp_connection:open_channel(Client) of
            {ok, Channel} ->
              pg2:join(AmqpParams, Channel),
              {ok, Channel};
            {error, Reason} -> {error, Reason}
          end;
        {error, Reason} -> {error, Reason}
      end;
    Channel -> 
                                                % io:format("using existing channel: ~p~n", [Channel]),
      {ok, Channel}
  end.

amqp_p(RObj) ->
  Metadata = riak_object:get_metadatas(RObj),

  Host = find(?HOST, Metadata, <<"127.0.0.1">>),
  Port = find(?PORT, Metadata, 5672),
  Vhost = find(?VHOST, Metadata, <<"/">>),
  User = find(?USER, Metadata, <<"guest">>),
  Pass = find(?PASSWORD, Metadata, <<"guest">>),

  #amqp_params{username = User,
               password = Pass,
               virtual_host = Vhost,
               host = binary_to_list(Host),
               port = Port}.

find(K, L, Default) ->
  case lists:keyfind(K, 1, L) of
    {K, V} -> V;
    _ -> Default
  end.
  
key_find(K, D, Default) ->
  case dict:find(K, D) of
    {ok, V} -> V;
    _ -> Default
  end.
