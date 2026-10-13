import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicBoardPanel from "../../../../admin/components/ingenic-board-panel";
import { i18n } from "discourse-i18n";

const Boards = <template>
  <div class="ingenic-admin__boards admin-detail">
    <DPageSubheader
      @titleLabel={{i18n "admin.ingenic.boards.title"}}
      @descriptionLabel={{i18n "admin.ingenic.boards.description"}}
    />
    <IngenicBoardPanel @boards={{@model.boards}} />
  </div>
</template>;

export default Boards;
