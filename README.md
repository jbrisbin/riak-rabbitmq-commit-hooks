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
    tar -zxvf $HOME/Downloads/riak_rabbitmq-0.1.0-R14B02.tar.gz

This should give you three new directories alongside `riak_kv-0.14.1` and the other 
libraries:

    amqp_client-2.4.1
    rabbit_common-2.4.1
    riak_rabbitmq-0.1.0

You can also clone the source, build, and then symlink the required dependencies 
into your Riak install:

    git clone git://github.com/jbrisbin/riak-rabbitmq-commit-hooks.git
    cd riak-rabbitmq-commit-hooks
    ./rebar get-deps
    make
    [...wait for a long time while spidermonkey builds...]
    cd $RIAK_LIBS
    ln -s $BUILD_DIR riak_rabbitmq-0.1.0
    ln -s $BUILD_DIR/deps/amqp_client amqp_client-2.4.1
    ln -s $BUILD_DIR/deps/rabbit_common rabbit_common-2.4.1

Either of these install methods should expose the module and the right dependencies 
to your Riak server.

### Configuration

To tell the commit hook where to send your entry in the form of an AMQP message, 
you can pass special metadata properties to influence the commit hook's behaviour. 
The list of acceptable properties is pretty self-explanatory:

* `X-Riak-Meta-AMQP-Exchange`
* `X-Riak-Meta-AMQP-Routing-Key`
* `X-Riak-Meta-AMQP-Host`
* `X-Riak-Meta-AMQP-Port`
* `X-Riak-Meta-AMQP-VHost`
* `X-Riak-Meta-AMQP-User`
* `X-Riak-Meta-AMQP-Password`

This utility is Apache licensed, just like Riak.