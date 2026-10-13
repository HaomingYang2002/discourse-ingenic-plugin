import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicResourceForm from "../../../../../admin/components/ingenic-resource-form";
import { i18n } from "discourse-i18n";

const BoardShow = <template>
  <div class="ingenic-admin__board-show admin-detail">
    <DPageSubheader
      @titleLabel={{@model.board.name}}
      @descriptionLabel={{i18n "admin.ingenic.boards.edit_description"}}
    />
    <IngenicResourceForm @resource="board" @record={{@model.board}} />
  </div>
</template>;

export default BoardShow;
