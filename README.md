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

I haven't had time to create a binary download yet. In the interest of early 
adoption, you're free to build and install from source. But if you can wait 
a day or two, I'll have a binary build up. :)

To install this module, clone the source, build, then symlink the required 
dependencies into your Riak install:

    git clone git://github.com/jbrisbin/riak-rabbitmq-commit-hooks.git
    cd riak-rabbitmq-commit-hooks
    ./rebar get-deps
    make
    [...wait for a long time while spidermonkey builds...]
    cd $RIAK_LIBS
    ln -s $BUILD_DIR riak_rabbitmq-0.1.0
    ln -s $BUILD_DIR/deps/amqp_client amqp_client-2.4.1
    ln -s $BUILD_DIR/deps/rabbit_common rabbit_common-2.4.1

This should expose the module and the right dependencies to your Riak server so 
that your postcommit hook will actually work.

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