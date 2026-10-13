import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { i18n } from "discourse-i18n";
import getURL from "discourse/lib/get-url";
import DNativeSelect from "discourse/ui-kit/d-native-select";

const ENDPOINT = "/ingenic/boards";

/**
 * Development board catalogue.
 *
 * A board is applied for or bought from the Ingenic team, so this page sells
 * nothing and takes no orders: every card ends in a link that leaves the forum.
 *
 * The two filters read the same product tree the documentation is organised by,
 * which is what keeps a board filed under T33 from disagreeing with the T33
 * pages. Both are answered by the server, so a board filed against a chip that
 * has since been renamed is still found under the name the tree now carries.
 */
export default class IngenicBoards extends Component {
  @tracked boards = [];
  @tracked filters = { series: [], chips: [] };
  @tracked series = "";
  @tracked chip = "";
  @tracked loading = true;

  // A chip belongs to exactly one series, so choosing a series narrows the chip
  // list rather than offering every chip on the site and then rejecting most of
  // them.
  get chipOptions() {
    if (!this.series) {
      return this.filters.chips;
    }

    return this.filters.chips.filter((item) => item.series_slug === this.series);
  }

  // Worked out here so the template stays a description of the layout. The
  // specification list is free text, one item per line.
  //
  // A board that is sold leads with the price and one that is not leads with the
  // application: a card whose only button is a plain one reads as an
  // afterthought, and only one of the two can be the thing to do first.
  get cards() {
    return this.boards.map((board) => ({
      ...board,
      specs: (board.specs ?? "")
        .split("\n")
        .map((line) => line.trim())
        .filter(Boolean),
      applyClass: board.purchase_url ? "btn" : "btn btn-primary",
    }));
  }

  get filtered() {
    return this.series !== "" || this.chip !== "";
  }

  @action
  async load() {
    this.loading = true;

    const query = new URLSearchParams();
    if (this.series) {
      query.set("series", this.series);
    }
    if (this.chip) {
      query.set("chip", this.chip);
    }

    const suffix = query.toString();

    try {
      const response = await fetch(
        getURL(suffix ? `${ENDPOINT}?${suffix}` : ENDPOINT),
        { headers: { Accept: "application/json" } }
      );

      if (response.ok) {
        const payload = await response.json();
        this.boards = payload.boards ?? [];
        this.filters = payload.filters ?? this.filters;
      }
    } catch {
      this.boards = [];
    } finally {
      this.loading = false;
    }
  }

  @action
  pickSeries(value) {
    this.series = value ?? "";
    // The chip that was chosen may not belong to the series just picked, and a
    // filter the visitor cannot see the reason for reads as an empty catalogue.
    this.chip = "";
    return this.load();
  }

  @action
  pickChip(value) {
    this.chip = value ?? "";
    return this.load();
  }

  @action
  clear(event) {
    event.preventDefault();
    this.series = "";
    this.chip = "";
    return this.load();
  }

  <template>
    <section class="ingenic-section" {{didInsert this.load}}>
      <header class="ingenic-section__header">
        <div>
          <h1>{{i18n (themePrefix "ingenic.boards.title")}}</h1>
          <p class="ingenic-section__subtitle">
            {{i18n (themePrefix "ingenic.boards.subtitle")}}
          </p>
        </div>
      </header>

      <div class="ingenic-boards__filters">
        <label class="ingenic-docs__field">
          <span>{{i18n (themePrefix "ingenic.boards.all_series")}}</span>
          <DNativeSelect
            @value={{this.series}}
            @nonePlaceholder={{i18n (themePrefix "ingenic.boards.all_series")}}
            @onChange={{this.pickSeries}}
            as |select|
          >
            {{#each this.filters.series as |item|}}
              <select.Option @value={{item.slug}}>{{item.name}}</select.Option>
            {{/each}}
          </DNativeSelect>
        </label>

        <label class="ingenic-docs__field">
          <span>{{i18n (themePrefix "ingenic.boards.all_chips")}}</span>
          <DNativeSelect
            @value={{this.chip}}
            @nonePlaceholder={{i18n (themePrefix "ingenic.boards.all_chips")}}
            @onChange={{this.pickChip}}
            as |select|
          >
            {{#each this.chipOptions as |item|}}
              <select.Option @value={{item.slug}}>{{item.name}}</select.Option>
            {{/each}}
          </DNativeSelect>
        </label>

        {{#if this.filtered}}
          <button class="btn btn-default" type="button" {{on "click" this.clear}}>
            {{i18n (themePrefix "ingenic.boards.clear_filters")}}
          </button>
        {{/if}}
      </div>

      {{#if this.boards.length}}
        <div class="ingenic-card-grid">
          {{#each this.cards as |board|}}
            <article class="ingenic-card ingenic-card--board">
              {{#if board.image_url}}
                <img
                  class="ingenic-card__image"
                  src={{board.image_url}}
                  alt={{board.name}}
                  loading="lazy"
                />
              {{/if}}

              <div class="ingenic-card__title">{{board.name}}</div>

              {{#if board.chip_name}}
                <div class="ingenic-card__meta">
                  {{board.chip_name}}
                  {{#if board.series_name}}· {{board.series_name}}{{/if}}
                </div>
              {{/if}}

              {{#if board.description}}
                <p>{{board.description}}</p>
              {{/if}}

              {{#if board.specs.length}}
                <ul class="ingenic-card__specs">
                  {{#each board.specs as |line|}}
                    <li>{{line}}</li>
                  {{/each}}
                </ul>
              {{/if}}

              <div class="ingenic-card__actions">
                {{#if board.purchase_url}}
                  <a
                    class="btn btn-primary"
                    href={{board.purchase_url}}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {{i18n (themePrefix "ingenic.boards.buy")}}
                  </a>
                {{/if}}

                {{#if board.application_url}}
                  <a
                    class={{board.applyClass}}
                    href={{board.application_url}}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {{i18n (themePrefix "ingenic.boards.apply")}}
                  </a>
                {{/if}}

                {{#if board.documentation_url}}
                  <a
                    class="btn"
                    href={{board.documentation_url}}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {{i18n (themePrefix "ingenic.boards.documentation")}}
                  </a>
                {{/if}}
              </div>
            </article>
          {{/each}}
        </div>
      {{else if this.loading}}
        <p class="ingenic-card__meta">…</p>
      {{else if this.filtered}}
        <p class="ingenic-card__meta">{{i18n (themePrefix "ingenic.boards.no_match")}}</p>
      {{else}}
        <p class="ingenic-card__meta">{{i18n (themePrefix "ingenic.boards.empty")}}</p>
      {{/if}}
    </section>
  </template>
}
