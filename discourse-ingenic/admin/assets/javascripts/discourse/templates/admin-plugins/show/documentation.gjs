import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicDocManager from "../../../../admin/components/ingenic-doc-manager";
import { i18n } from "discourse-i18n";

const Documentation = <template>
  <div class="ingenic-admin__documentation admin-detail">
    <DPageSubheader
      @titleLabel={{i18n "admin.ingenic.documentation.title"}}
      @descriptionLabel={{i18n "admin.ingenic.documentation.description"}}
    />
    <IngenicDocManager @series={{@model.series}} />
  </div>
</template>;

export default Documentation;
