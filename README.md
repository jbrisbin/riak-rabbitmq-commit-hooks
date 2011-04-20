# Riak RabbitMQ postcommit hook

This is a postcommit hook that sends entries into a RabbitMQ broker using the 
Erlang AMQP client.

You set this module/function as your postcommit hook using whatever tools you're 
used to. Your bucket properties should look something like this:

    {
      "props":{
        "postcommit":[{"mod":"riak_rabbitmq","fun":"postcommit_send_amqp"}],
        ... other props ...
      }
    }

### Installation

To install from the binary (compiled with Erlang R14B02), download the tar.gz file. 
cd into the Riak `lib` directory. For example, Homebrew users on a Mac would:

    cd /usr/local/Cellar/riak/0.14.1/libexec/lib
    tar -zxvf $HOME/Downloads/riak_rabbitmq-0.1.3-R14B02.tar.gz

This should give you three new directories alongside `riak_kv-0.14.1` and the other 
libraries:

    amqp_client-2.4.1
    rabbit_common-2.4.1
    riak_rabbitmq-0.1.3

You can also clone the source, build, and then symlink the required dependencies 
into your Riak install:

    git clone git://github.com/jbrisbin/riak-rabbitmq-commit-hooks.git
    cd riak-rabbitmq-commit-hooks
    ./rebar get-deps
    make
    [...wait for a long time while spidermonkey builds...]
    cd $RIAK_LIBS
    ln -s $BUILD_DIR riak_rabbitmq-0.1.3
    ln -s $BUILD_DIR/deps/amqp_client amqp_client-2.4.1
    ln -s $BUILD_DIR/deps/rabbit_common rabbit_common-2.4.1

Either of these install methods should expose the module and the right dependencies 
to your Riak server.

### Configuration

To tell the commit hook where to send your entry in the form of an AMQP message, 
you can pass special metadata properties to influence the commit hook's behaviour. 
The list of acceptable properties is pretty self-explanatory:

* `X-Riak-Meta-Amqp-Exchange`
* `X-Riak-Meta-Amqp-Routing-Key`
* `X-Riak-Meta-Amqp-Host`
* `X-Riak-Meta-Amqp-Port`
* `X-Riak-Meta-Amqp-Vhost`
* `X-Riak-Meta-Amqp-User`
* `X-Riak-Meta-Amqp-Password`

Alternatively, you can specify settings for an entire bucket by setting these metadata headers 
on an empty document at the key `AMQP-Meta` in the bucket you want to configure.

This allows you to route entries in an entire bucket to specific RabbitMQ servers without 
your publisher having to know this information ahead of time.

### Ignore Flag

If you don't want a particular entry in a RabbitMQ-enabled bucket to actually be sent out 
(like if you're updating the `AMQP-Meta` entry), then set a metadata header with the name 
`X-Riak-Meta-Amqp-Ignore` to the string "true". The postcommit hook will see this flag and 
not actually send any message.

### Deleted Entries

If the update operation is a DELETE, the postcommit hook will set an AMQP message header named 
`X-Riak-Deleted` to "true". This way your application can distinguish between updates and deletes.

This utility is Apache licensed, just like Riak.
