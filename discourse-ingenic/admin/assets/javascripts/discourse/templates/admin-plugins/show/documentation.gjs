import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicAdminPanel from "../../../../admin/components/ingenic-admin-panel";
import { i18n } from "discourse-i18n";

const Documentation = <template>
  <div class="ingenic-admin__documentation admin-detail">
    <DPageSubheader
      @titleLabel={{i18n "admin.ingenic.documentation.title"}}
      @descriptionLabel={{i18n "admin.ingenic.documentation.description"}}
    />
    <IngenicAdminPanel @kind="documentation" @model={{@model}} />
  </div>
</template>;

export default Documentation;
