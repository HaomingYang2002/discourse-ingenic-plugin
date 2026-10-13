import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicAdminPanel from "../../../../admin/components/ingenic-admin-panel";
import { i18n } from "discourse-i18n";

const Boards = <template>
  <div class="ingenic-admin__boards admin-detail">
    <DPageSubheader
      @titleLabel={{i18n "admin.ingenic.boards.title"}}
      @descriptionLabel={{i18n "admin.ingenic.boards.description"}}
    />
    <IngenicAdminPanel @kind="boards" @model={{@model}} />
  </div>
</template>;

export default Boards;
