class TestChannel < ApplicationCable::Channel
  def subscribed
    stream_from "test"
  end

  def receive(data)
    ActionCable.server.broadcast("test", data)
  end
end
