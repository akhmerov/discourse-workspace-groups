export default function () {
  this.route("workspace-voice", function () {
    this.route("channel", { path: "/channels/:category_id" });
    this.route("dm", { path: "/dms/:channel_id" });
  });
}
