import { themePrefix } from "virtual:theme";
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import getURL from "discourse/lib/get-url";
import DNativeSelect from "discourse/ui-kit/d-native-select";

const ENDPOINT = "/ingenic/boards";

/**
 * Development board and sample chip catalogue.
 *
 * These are applied for or bought from the Ingenic team, so this page sells
 * nothing and takes no orders: every card ends in a link that leaves the forum.
 *
 * The filters are two levels. The first chooses the kind of thing — a board or
 * a sample — and is drawn as two buttons rather than a select, because it is a
 * choice between two named things and a closed select would hide the second
 * until it was opened. The second chooses the chip, and is a select because
 * there are as many chips as the product tree holds.
 *
 * A card is a shop window: picture, name, a short introduction, and the two
 * links. Everything longer — the full description and the specifications —
 * is in the dialog the card opens, so the grid stays the same height whatever
 * was written for each item.
 */
export default class IngenicBoards extends Component {
  @tracked boards = [];
  @tracked filters = { kinds: ["board", "sample"], chips: [] };
  @tracked kind = "board";
  @tracked chip = "";
  @tracked selected = null;
  @tracked loading = true;

  // Answers can arrive out of order — a kind is one click away from the next,
  // and the page is often read over a slow link — so each load remembers which
  // request it is and only the newest is allowed to write the results. Without
  // this, switching tabs quickly can leave one kind's boards under the other
  // kind's heading.
  requestId = 0;

  get kindTabs() {
    const kinds = this.filters.kinds?.length
      ? this.filters.kinds
      : ["board", "sample"];

    return kinds.map((kind) => ({
      kind,
      label: i18n(themePrefix(`ingenic.boards.kind_${kind}`)),
      active: kind === this.kind,
    }));
  }

  // Every chip, each labelled with the series it belongs to: without a series
  // filter on this page, "T33" on its own is not enough context to choose
  // from.
  get chipOptions() {
    return this.filters.chips;
  }

  // Worked out here so the template stays a description of the layout. The
  // specification list is free text, one item per line.
  //
  // A board that is sold leads with the price and one that is not leads with
  // the application: a card whose only button is a plain one reads as an
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
    return this.chip !== "";
  }

  @action
  async load() {
    const request = ++this.requestId;
    this.loading = true;

    const query = new URLSearchParams();
    if (this.kind) {
      query.set("kind", this.kind);
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

        if (request === this.requestId) {
          this.boards = payload.boards ?? [];
          this.filters = payload.filters ?? this.filters;
        }
      }
    } catch {
      if (request === this.requestId) {
        this.boards = [];
      }
    } finally {
      if (request === this.requestId) {
        this.loading = false;
      }
    }
  }

  @action
  pickKind(kind) {
    if (kind === this.kind) {
      return;
    }

    this.kind = kind;
    // The chip that was chosen may not have anything of the kind just picked,
    // and a filter the visitor cannot see the reason for reads as an empty
    // catalogue.
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
    this.chip = "";
    return this.load();
  }

  @action
  chipLabel(chip) {
    return chip.series_name
      ? `${chip.series_name} › ${chip.name}`
      : chip.name;
  }

  // The whole card is the way into the detail dialog, so the two links have to
  // stop their own clicks from also opening it — they leave the site, and the
  // browser is already doing what was asked.
  @action
  open(board) {
    this.selected = board;
  }

  @action
  close() {
    this.selected = null;
  }

  @action
  stop(event) {
    event.stopPropagation();
  }

  @action
  openFromKeyboard(board, event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.open(board);
    }
  }

  @action
  onKeydown(event) {
    if (event.key === "Escape" && this.selected) {
      this.close();
    }
  }

  @action
  focusDialog(element) {
    element.focus();
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
        <div class="ingenic-boards__kinds" role="tablist">
          {{#each this.kindTabs as |tab|}}
            <button
              class="ingenic-boards__kind {{if tab.active 'is-current'}}"
              type="button"
              role="tab"
              aria-selected={{tab.active}}
              {{on "click" (fn this.pickKind tab.kind)}}
            >
              {{tab.label}}
            </button>
          {{/each}}
        </div>

        <label class="ingenic-docs__field ingenic-boards__chip">
          <span>{{i18n (themePrefix "ingenic.boards.chip_filter")}}</span>
          <DNativeSelect
            @value={{this.chip}}
            @nonePlaceholder={{i18n (themePrefix "ingenic.boards.all_chips")}}
            @onChange={{this.pickChip}}
            as |select|
          >
            {{#each this.chipOptions as |item|}}
              <select.Option @value={{item.slug}}>
                {{this.chipLabel item}}
              </select.Option>
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
        <div class="ingenic-card-grid ingenic-card-grid--products">
          {{#each this.cards as |board|}}
            <article
              class="ingenic-product-card"
              tabindex="0"
              role="button"
              {{on "click" (fn this.open board)}}
              {{on "keydown" (fn this.openFromKeyboard board)}}
            >
              <div class="ingenic-product-card__media">
                {{#if board.image_url}}
                  <img
                    class="ingenic-product-card__image"
                    src={{board.image_url}}
                    alt={{board.name}}
                    loading="lazy"
                  />
                {{else}}
                  <span class="ingenic-product-card__placeholder" aria-hidden="true">
                    {{dIcon "microchip"}}
                  </span>
                {{/if}}
              </div>

              <div class="ingenic-product-card__body">
                <h2 class="ingenic-product-card__name">{{board.name}}</h2>

                {{#if board.chip_name}}
                  <div class="ingenic-product-card__meta">
                    {{board.chip_name}}
                    {{#if board.series_name}}· {{board.series_name}}{{/if}}
                  </div>
                {{/if}}

                {{#if board.description}}
                  <p class="ingenic-product-card__description">
                    {{board.description}}
                  </p>
                {{/if}}
              </div>

              <div class="ingenic-product-card__actions">
                {{#if board.application_url}}
                  <a
                    class={{board.applyClass}}
                    href={{board.application_url}}
                    target="_blank"
                    rel="noopener noreferrer"
                    {{on "click" this.stop}}
                  >
                    {{i18n (themePrefix "ingenic.boards.apply")}}
                  </a>
                {{/if}}

                {{#if board.purchase_url}}
                  <a
                    class="btn btn-primary"
                    href={{board.purchase_url}}
                    target="_blank"
                    rel="noopener noreferrer"
                    {{on "click" this.stop}}
                  >
                    {{i18n (themePrefix "ingenic.boards.buy")}}
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

      {{#if this.selected}}
        <div
          class="ingenic-board-dialog"
          role="dialog"
          aria-modal="true"
          tabindex="-1"
          {{didInsert this.focusDialog}}
          {{on "click" this.close}}
          {{on "keydown" this.onKeydown}}
        >
          <div class="ingenic-board-dialog__panel" {{on "click" this.stop}}>
            <button
              class="ingenic-board-dialog__close"
              type="button"
              aria-label={{i18n (themePrefix "ingenic.boards.close")}}
              {{on "click" this.close}}
            >
              ×
            </button>

            <div class="ingenic-board-dialog__scroll">
              {{#if this.selected.image_url}}
                <div class="ingenic-board-dialog__media">
                  <img
                    class="ingenic-board-dialog__image"
                    src={{this.selected.image_url}}
                    alt={{this.selected.name}}
                  />
                </div>
              {{/if}}

              <h2 class="ingenic-board-dialog__title">{{this.selected.name}}</h2>

              {{#if this.selected.chip_name}}
                <div class="ingenic-board-dialog__meta">
                  {{this.selected.chip_name}}
                  {{#if this.selected.series_name}}· {{this.selected.series_name}}{{/if}}
                </div>
              {{/if}}

              {{#if this.selected.details}}
                <p class="ingenic-board-dialog__details">{{this.selected.details}}</p>
              {{else if this.selected.description}}
                <p class="ingenic-board-dialog__details">{{this.selected.description}}</p>
              {{/if}}

              {{#if this.selected.specs.length}}
                <ul class="ingenic-board-dialog__specs">
                  {{#each this.selected.specs as |line|}}
                    <li>{{line}}</li>
                  {{/each}}
                </ul>
              {{/if}}

              {{#if this.selected.documentation_url}}
                <a
                  class="ingenic-board-dialog__documentation"
                  href={{this.selected.documentation_url}}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {{i18n (themePrefix "ingenic.boards.documentation")}}
                </a>
              {{/if}}
            </div>

            <div class="ingenic-board-dialog__actions">
              {{#if this.selected.application_url}}
                <a
                  class="btn"
                  href={{this.selected.application_url}}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {{i18n (themePrefix "ingenic.boards.apply")}}
                </a>
              {{/if}}

              {{#if this.selected.purchase_url}}
                <a
                  class="btn btn-primary"
                  href={{this.selected.purchase_url}}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {{i18n (themePrefix "ingenic.boards.buy")}}
                </a>
              {{/if}}
            </div>
          </div>
        </div>
      {{/if}}
    </section>
  </template>
}
