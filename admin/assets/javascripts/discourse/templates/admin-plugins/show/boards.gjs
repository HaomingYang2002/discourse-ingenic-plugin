import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicBoardManager from "../../../../admin/components/ingenic-board-manager";
import { i18n } from "discourse-i18n";

const Boards = <template>
  <div class="admin-detail">
    <DPageSubheader
      @titleLabel={{i18n "admin.ingenic.boards.title"}}
      @descriptionLabel={{i18n "admin.ingenic.boards.description"}}
    />
    <IngenicBoardManager
      @boards={{@model.boards}}
      @chips={{@model.chips}}
      @locales={{@model.locales}}
    />
  </div>
</template>;

export default Boards;
