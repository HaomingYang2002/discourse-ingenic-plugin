import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { i18n } from "discourse-i18n";

export default class IngenicBlockSearch extends Component {
  @service router;
  @tracked query = "";

  @action
  submit(event) {
    event.preventDefault();

    const query = this.query.trim();
    if (query) {
      this.router.transitionTo(`/search?q=${encodeURIComponent(query)}`);
    }
  }

  @action
  update(event) {
    this.query = event.target.value;
  }

  <template>
    <section class="ingenic-section ingenic-hero">
      <form class="ingenic-search" {{on "submit" this.submit}}>
        <input
          type="search"
          class="ingenic-search__input"
          placeholder={{i18n (themePrefix "ingenic.home.search_placeholder")}}
          value={{this.query}}
          {{on "input" this.update}}
        />
      </form>
    </section>
  </template>
}
