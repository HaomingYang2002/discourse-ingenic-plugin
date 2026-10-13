import DPageSubheader from "discourse/ui-kit/d-page-subheader";
import IngenicPermissionForm from "../../../../admin/components/ingenic-permission-form";
import IngenicPermissionList from "../../../../admin/components/ingenic-permission-list";
import { i18n } from "discourse-i18n";

const Permissions = <template>
  <div class="ingenic-admin__permissions admin-detail">
    <DPageSubheader
      @titleLabel={{i18n "admin.ingenic.permissions.title"}}
      @descriptionLabel={{i18n "admin.ingenic.permissions.description"}}
    />
    <IngenicPermissionForm />
    <IngenicPermissionList @permissions={{@model.permissions}} />
  </div>
</template>;

export default Permissions;
