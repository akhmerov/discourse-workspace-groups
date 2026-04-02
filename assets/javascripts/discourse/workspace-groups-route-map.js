export default {
  resource: "discovery",
  path: "/",
  map() {
    this.route("workspaceOverview", {
      path: "/c/*category_slug_path_with_id/overview",
    });
  },
};
