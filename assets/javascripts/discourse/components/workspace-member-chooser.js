import { ajax } from "discourse/lib/ajax";
import { selectKitOptions } from "discourse/select-kit/components/select-kit";
import UserChooser from "discourse/select-kit/components/user-chooser";
import WorkspaceMemberRow from "./workspace-member-row";

@selectKitOptions({ memberSearchUrl: undefined })
export default class WorkspaceMemberChooser extends UserChooser {
  modifyComponentForRow() {
    return WorkspaceMemberRow;
  }

  search(filter = "") {
    const term = (filter || "").replace(/^@/, "").trim();
    if (!term) {
      return [];
    }

    return ajax(this.selectKit.options.memberSearchUrl, {
      data: { term, exclude: (this.value || []).join(",") },
    }).then((result) => result.users);
  }
}
