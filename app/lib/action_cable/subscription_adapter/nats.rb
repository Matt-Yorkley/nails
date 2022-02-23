# frozen_string_literal: true

require 'nats/client'

module ActionCable
  module SubscriptionAdapter
    class Nats < Base
      prepend ChannelPrefix

      def initialize(*)
        super
        @listener = nil
        @nats = NATS.connect ENV.fetch("NATS_CABLE_SERVER", "127.0.0.1")
        @connection_for_broadcasts = nil
      end

      def broadcast(channel, payload)
        connection_for_broadcasts.publish(channel, payload)
      end

      def subscribe(channel, callback, success_callback = nil)
        listener.add_subscriber(channel, callback, success_callback)
      end

      def unsubscribe(channel, callback)
        listener.remove_subscriber(channel, callback)
      end

      def shutdown
        listener.shutdown
      end

      def connection_for_subscriptions
        nats
      end

      private

      attr_reader :nats

      def listener
        @listener || @server.mutex.synchronize { @listener ||= Listener.new(self, @server.event_loop) }
      end

      def connection_for_broadcasts
        @connection_for_broadcasts || @server.mutex.synchronize do
          @connection_for_broadcasts ||= nats
        end
      end

      class Listener < SubscriberMap
        def initialize(adapter, event_loop)
          super()

          @adapter = adapter
          @event_loop = event_loop
          @queue = Queue.new

          @thread = Thread.new do
            Thread.current.abort_on_exception = true

            Rails.application.executor.wrap do
              listen @adapter.connection_for_subscriptions
            end
          end
        end

        def listen(connection)
          catch :shutdown do
            loop do
              until @queue.empty?
                action, channel, callback = @queue.pop(true)

                case action
                when :listen
                  connection.subscribe(channel) do |msg|
                    broadcast channel, msg.data
                  end
                  @event_loop.post(&callback) if callback
                when :unlisten
                  subscription(connection, channel)&.unsubscribe
                when :shutdown
                  throw :shutdown
                end
              end

              Thread.pass
            end
          end
        end

        def shutdown
          @queue.push([:shutdown])

          return if @thread.nil?

          Thread.pass while @thread.alive?
        end

        def add_channel(channel, on_success)
          @queue.push([:listen, channel, on_success])
        end

        def remove_channel(channel)
          @queue.push([:unlisten, channel])
        end

        def invoke_callback(*)
          @event_loop.post { super }
        end

        private

        def subscription(connection, channel)
          subscriptions(connection).
            select{|_sid, subscription| subscription.subject == channel }.values.first
        end

        def subscriptions(connection)
          connection.instance_variable_get("@subs")
        end
      end
    end
  end
end
