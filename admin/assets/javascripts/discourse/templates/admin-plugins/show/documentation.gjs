import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicDocManager from "../../../../admin/components/ingenic-doc-manager";
import { i18n } from "discourse-i18n";

const Documentation = <template>
  <div class="admin-detail">
    <DPageSubheader
      @titleLabel={{i18n "admin.ingenic.documentation.title"}}
      @descriptionLabel={{i18n "admin.ingenic.documentation.description"}}
    />
    <IngenicDocManager
      @series={{@model.series}}
      @locales={{@model.locales}}
      @defaultLocale={{@model.default_locale}}
    />
  </div>
</template>;

export default Documentation;
