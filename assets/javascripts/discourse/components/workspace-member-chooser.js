import { ajax } from "discourse/lib/ajax";
import { extractError } from "discourse/lib/ajax-error";
import { selectKitOptions } from "discourse/select-kit/components/select-kit";
import UserChooser from "discourse/select-kit/components/user-chooser";
import WorkspaceMemberRow from "./workspace-member-row";

@selectKitOptions({ memberSearchUrl: undefined })
export default class WorkspaceMemberChooser extends UserChooser {
  modifyComponentForRow() {
    return WorkspaceMemberRow;
  }

  search(filter = "") {
    const sequence = (this._memberSearchSequence || 0) + 1;
    this._memberSearchSequence = sequence;
    const term = (filter || "").replace(/^@/, "").trim();
    const request = term
      ? ajax(this.selectKit.options.memberSearchUrl, {
          data: { term, exclude: (this.value || []).join(",") },
        }).then((result) => result.users)
      : Promise.resolve([]);

    const result = request
      .catch((error) => {
        if (
          sequence === this._memberSearchSequence &&
          !this.isDestroyed &&
          !this.isDestroying
        ) {
          this.addError(extractError(error));
        }
        return [];
      })
      .then((users) => {
        if (this.isDestroyed || this.isDestroying) {
          return [];
        }
        // SelectKit applies every resolved search. Older searches must follow
        // the latest promise, including a cleared filter or another new search.
        return sequence === this._memberSearchSequence
          ? users
          : this._latestMemberSearch;
      });
    this._latestMemberSearch = result;
    return result;
  }
}
