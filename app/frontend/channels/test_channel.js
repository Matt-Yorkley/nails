import consumer from './consumer'

window.Test = consumer.subscriptions.create("TestChannel", {
  received(data) {
    console.log("Received:")
    console.log(data)
  }
});
