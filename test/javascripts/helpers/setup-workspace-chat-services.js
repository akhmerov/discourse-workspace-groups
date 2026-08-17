import Service from "@ember/service";

class ChatServiceStub extends Service {
  async loadChannels() {}
}

class ChatChannelsManagerStub extends Service {
  channels = [];

  find() {}

  follow() {}

  remove() {}

  store() {}
}

export function setupWorkspaceChatServices(hooks) {
  hooks.beforeEach(function () {
    this.owner.register("service:chat", ChatServiceStub);
    this.owner.register(
      "service:chat-channels-manager",
      ChatChannelsManagerStub
    );
  });
}
