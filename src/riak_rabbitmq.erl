-module(riak_rabbitmq).
-include_lib("amqp_client/include/amqp_client.hrl").

-export([
  postcommit_send_amqp/1
]).

-define(BUCKET_META, <<"AMQP-Meta">>).
-define(DELETED, <<"X-Riak-Deleted">>).
-define(META, <<"X-Riak-Meta">>).
-define(EXCHANGE, "X-Riak-Meta-Amqp-Exchange").
-define(ROUTING_KEY, "X-Riak-Meta-Amqp-Routing-Key").
-define(HOST, "X-Riak-Meta-Amqp-Host").
-define(PORT, "X-Riak-Meta-Amqp-Port").
-define(VHOST, "X-Riak-Meta-Amqp-Vhost").
-define(USER, "X-Riak-Meta-Amqp-User").
-define(PASSWORD, "X-Riak-Meta-Amqp-Password").
-define(SKIP, "X-Riak-Meta-Amqp-Ignore").

-define(CONTENT_TYPE, <<"content-type">>).

postcommit_send_amqp(RObj) ->
  {ok, C} = riak:local_client(),
  PerBucketMetaObj = case C:get(riak_object:bucket(RObj), ?BUCKET_META) of
    {ok, PBMO} -> PBMO;
    _ -> none
  end,
  % lager:log(info, "bucket meta obj: ~p", [PerBucketMetaObj]),
  PerBucketMeta = case PerBucketMetaObj of
    none -> none;
    _ -> 
      PBM = riak_object:get_metadata(PerBucketMetaObj),
      key_find(?META, PBM, none, [])
  end,
  % io:format("bucket meta: ~p~n", [PerBucketMeta]),
  Metadata = riak_object:get_metadata(RObj),
  Exchange = key_find(?EXCHANGE, Metadata, PerBucketMeta, riak_object:bucket(RObj)),
  % io:format("exchange: ~s~n", [Exchange]),
  RoutingKey = key_find(?ROUTING_KEY, Metadata, PerBucketMeta, riak_object:key(RObj)),
  % io:format("routing key: ~s~n", [RoutingKey]),
  ContentType = list_to_binary(key_find(?CONTENT_TYPE, Metadata, PerBucketMeta, "application/octet-stream")),
  Body = riak_object:get_value(RObj),

  % Publish a message
  Publish = #'basic.publish'{ exchange=Exchange, routing_key=RoutingKey },
  Headers = key_find(?META, Metadata, none, []),
  
  case find(?SKIP, Headers, [], "false") of
    "true" -> ok;
    _ ->
      AppHdrs = lists:foldl(fun ({HdrKey, HdrValue}, NewHdrs) ->
                                <<_:12/binary, Key/binary>> = list_to_binary(HdrKey),
                                [{binary_to_list(Key), binary, HdrValue} | NewHdrs]
                            end, [], Headers),
      ExtraHdrs = [case key_find(?DELETED, Metadata, none, "false") of
                     "true" -> {"X-Riak-Deleted", binary, "true"};
                     "false" -> []
                   end],
      Props = #'P_basic'{ content_type=ContentType, headers=lists:flatten([AppHdrs, ExtraHdrs]) },

      Msg = #amqp_msg{ payload=Body, props=Props },
      % io:format("message: ~p~n", [Msg]),
      {ok, Channel} = amqp_channel(RObj, PerBucketMetaObj),
      % io:format("channel: ~p~n", [Channel]),
      amqp_channel:cast(Channel, Publish, Msg),
      % io:format("published~n"),
      ok
  end.

amqp_channel(RObj, PerBucketMetaObj) ->
  AmqpParams = amqp_p(RObj, PerBucketMetaObj),
  % io:format("amqp params: ~p~n", [AmqpParams]),
  case pg2:get_closest_pid(AmqpParams) of
    {error, {no_such_group, _}} -> 
      pg2:create(AmqpParams),
      amqp_channel(RObj, PerBucketMetaObj);
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

amqp_p(RObj, PerBucketMetaObj) ->
  Metadata = riak_object:get_metadatas(RObj),
  PerBucketMetadata = case PerBucketMetaObj of
    none -> [];
    _ -> riak_object:get_metadatas(PerBucketMetaObj)
  end,

  Host = find(?HOST, Metadata, PerBucketMetadata, <<"127.0.0.1">>),
  Port = find(?PORT, Metadata, PerBucketMetadata, 5672),
  Vhost = find(?VHOST, Metadata, PerBucketMetadata, <<"/">>),
  User = find(?USER, Metadata, PerBucketMetadata, <<"guest">>),
  Pass = find(?PASSWORD, Metadata, PerBucketMetadata, <<"guest">>),

  #amqp_params_network{username = User,
                       password = Pass,
                       virtual_host = Vhost,
                       host = binary_to_list(Host),
                       port = Port}.

find(K, L, PerBucketMetadata, Default) ->
  case lists:keyfind(K, 1, L) of
    {K, V} -> V;
    _ -> 
      case PerBucketMetadata of
        none -> Default;
        _ ->
          case lists:keyfind(K, 1, PerBucketMetadata) of
            {K, BucketV} -> BucketV;
            _ -> Default
          end
      end
  end.
  
key_find(K, D, BucketMeta, Default) ->
  case dict:find(K, D) of
    {ok, V} -> V;
    _ -> 
      % io:format("per-bucket meta: ~p~n", [BucketMeta]),
      case BucketMeta of
        none -> Default;
        _ -> 
          case find(K, BucketMeta, none, Default) of
            PerBucketV when is_binary(PerBucketV) -> PerBucketV;
            PerBucketV -> list_to_binary(PerBucketV)
          end
      end
  end.
