-module(riak_rabbitmq).
-include_lib("amqp_client/include/amqp_client.hrl").

-export([
  postcommit_send_amqp/1
]).

-define(BUCKET_META, <<"AMQP-Meta">>).
-define(DELETED, <<"X-Riak-Deleted">>).
-define(META, <<"X-Riak-Meta">>).
-define(EXCHANGE, <<"X-Riak-Meta-Amqp-Exchange">>).
-define(ROUTING_KEY, <<"X-Riak-Meta-Amqp-Routing-Key">>).
-define(HOST, <<"X-Riak-Meta-Amqp-Host">>).
-define(PORT, <<"X-Riak-Meta-Amqp-Port">>).
-define(VHOST, <<"X-Riak-Meta-Amqp-Vhost">>).
-define(USER, <<"X-Riak-Meta-Amqp-User">>).
-define(PASSWORD, <<"X-Riak-Meta-Amqp-Password">>).
-define(SKIP, <<"X-Riak-Meta-Amqp-Ignore">>).

-define(CONTENT_TYPE, <<"content-type">>).

postcommit_send_amqp(RObj) ->
  
  MetadataObj = riak_object:get_metadata(RObj),
  Headers = key_find(?META, MetadataObj, none, []),
  % io:format("Obj meta: ~p~n", [MetadataObj]),
  % io:format("Obj headers: ~p~n", [Headers]),
    
  {ok, C} = riak:local_client(),
  PerBucketMetaObj = case C:get(riak_object:bucket(RObj), ?BUCKET_META) of
    {ok, PBMO} -> PBMO;
    _ -> none
  end,
  
  PerBucketHeaders = case PerBucketMetaObj of
    none -> none;
    _ -> 
      PBM = riak_object:get_metadata(PerBucketMetaObj),
      key_find(?META, PBM, none, [])
  end,
  % io:format("bucket meta: ~p~n", [PerBucketHeaders]),
  
  Exchange = find(?EXCHANGE, Headers, PerBucketHeaders, riak_object:bucket(RObj)),
  % io:format("exchange: ~s~n", [Exchange]),
  RoutingKey = find(?ROUTING_KEY, Headers, PerBucketHeaders, riak_object:key(RObj)),
  % io:format("routing key: ~s~n", [RoutingKey]),
  ContentType = list_to_binary(key_find(?CONTENT_TYPE, MetadataObj, PerBucketHeaders, "application/octet-stream")),
  Body = riak_object:get_value(RObj),

  % Publish a message
  Publish = #'basic.publish'{ exchange=Exchange, routing_key=RoutingKey },
  
  
  case find(?SKIP, Headers, [], "false") of
    "true" -> ok;
    _ ->
      AppHdrs = lists:foldl(fun ({HdrKey, HdrValue}, NewHdrs) ->
                                <<_:12/binary, Key/binary>> = HdrKey,
                                [{binary_to_list(Key), binary, HdrValue} | NewHdrs]
                            end, [], Headers),
      ExtraHdrs = [case key_find(?DELETED, MetadataObj, none, "false") of
                     "true" -> {"X-Riak-Deleted", binary, "true"};
                     "false" -> []
                   end],
      Props = #'P_basic'{ content_type=ContentType, headers=lists:flatten([AppHdrs, ExtraHdrs]) },

      Msg = #amqp_msg{ payload=Body, props=Props },
      % io:format("message: ~p~n", [Msg]),
      {ok, Channel} = amqp_channel(Headers, PerBucketHeaders),
      % io:format("channel: ~p~n", [Channel]),
      amqp_channel:cast(Channel, Publish, Msg),
      % io:format("published~n"),
      ok
  end.

amqp_channel(Headers, PerBucketMeta) ->
  AmqpParams = amqp_p(Headers, PerBucketMeta),
  % io:format("amqp params: ~p~n", [AmqpParams]),
  case pg2:get_closest_pid(AmqpParams) of
    {error, {no_such_group, _}} -> 
      pg2:create(AmqpParams),
      amqp_channel(Headers, PerBucketMeta);
    {error, {no_process, _}} -> 
      % io:format("no client running~n"),
      case amqp_connection:start(AmqpParams) of
        {ok, Client} ->
          % io:format("started new client: ~p~n", [Client]),
          case amqp_connection:open_channel(Client) of
            {ok, Channel} ->
              pg2:join(AmqpParams, Channel),
              {ok, Channel};
            {error, Reason} -> {error, Reason}
          end;
        {error, Reason} -> 
          % io:format("encountered an error: ~p~n", [Reason]),
          {error, Reason}
      end;
    Channel -> 
      % io:format("using existing channel: ~p~n", [Channel]),
      {ok, Channel}
  end.

amqp_p(Headers, PerBucketHeaders) ->
  
  % io:format("ObjMeta: ~p~n", [Headers]),
  % io:format("BucketMeta: ~p~n", [PerBucketHeaders]),
  
  Host = find(?HOST, Headers, PerBucketHeaders, <<"127.0.0.1">>),
  Port = find(?PORT, Headers, PerBucketHeaders, 5672),
  Vhost = find(?VHOST, Headers, PerBucketHeaders, <<"/">>),
  User = find(?USER, Headers, PerBucketHeaders, <<"guest">>),
  Pass = find(?PASSWORD, Headers, PerBucketHeaders, <<"guest">>),

  #amqp_params_network{username = User,
                       password = Pass,
                       virtual_host = Vhost,
                       host = binary_to_list(Host),
                       port = Port}.

find(K, L, PerBucketHeaders, Default) ->
  case lists:keyfind(K, 1, L) of
    {K, V} -> V;
    _ -> 
      case PerBucketHeaders of
        none -> Default;
        _ ->
          case lists:keyfind(K, 1, PerBucketHeaders) of
            {K, BucketV} -> BucketV;
            _ -> Default
          end
      end
  end.
  
key_find(K, D, PerBucketHeaders, Default) ->
  case dict:find(K, D) of
    {ok, V} -> V;
    _ -> 
      % io:format("per-bucket meta: ~p~n", [PerBucketHeaders]),
      case PerBucketHeaders of
        none -> Default;
        _ -> 
          case find(K, PerBucketHeaders, none, Default) of
            PerBucketV when is_binary(PerBucketV) -> PerBucketV;
            PerBucketV -> list_to_binary(PerBucketV)
          end
      end
  end.
