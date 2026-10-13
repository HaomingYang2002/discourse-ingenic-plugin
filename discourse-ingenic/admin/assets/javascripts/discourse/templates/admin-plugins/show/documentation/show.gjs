import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicDocEditor from "../../../../../admin/components/ingenic-doc-editor";
import { i18n } from "discourse-i18n";

const DocumentationShow = <template>
  <div class="ingenic-admin__documentation-show admin-detail">
    <DPageSubheader
      @titleLabel={{@model.product.name}}
      @descriptionLabel={{i18n "admin.ingenic.documentation.versions"}}
    />
    <IngenicDocEditor @product={{@model.product}} />
  </div>
</template>;

export default DocumentationShow;
