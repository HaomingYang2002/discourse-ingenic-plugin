# frozen_string_literal: true

module Ingenic
  # Turns the sparse per-version page rows into the complete document a reader
  # sees at one version.
  #
  # A version only stores the pages that were actually edited for it. Anything
  # untouched is inherited from the versions before it, so publishing a new
  # version does not mean duplicating the whole manual and then keeping every
  # copy in sync.
  #
  # Version order is the `position` column, lowest first, so moving a version
  # changes what inherits from what. Ties fall back to insertion order.
  class DocumentationResolver
    def initialize(product)
      @product = product
    end

    # Every version of the product, oldest first. There is no `published` flag on
    # a version to filter by — what a reader may see is decided page by page, and
    # a version with no pages of its own is not empty, it is the one before it.
    # Asking for a scope that does not exist raised `NoMethodError` on the first
    # request that resolved any documentation at all.
    def versions
      @versions ||= product.versions.to_a.sort_by { |version| [version.position, version.id] }
    end

    # Every version that contributes to `version`, oldest first and including
    # the version itself.
    def chain_for(version)
      versions.select { |candidate| candidate.position <= version.position }
    end

    # The version's pages in reading order: depth-first, parents before their
    # children, each carrying the depth the tree renders at.
    #
    # `published_only: false` is for the management page, which has to show
    # drafts that a reader would not see.
    #
    # `locale` is the language the caller is looking at. Readers omit it and
    # get their own locale; the management screen passes the language chosen at
    # the top of the workbench, because the admin's UI language and the manual
    # being edited are two different things. Without it, choosing English in a
    # Chinese admin panel resolved the tree in Chinese and the English pages
    # disappeared.
    def effective_pages(version, published_only: true, locale: nil)
      build_tree(effective_rows(version, published_only: published_only, locale: locale))
    end

    # Folders never resolve as a page: an address that names one is a broken
    # link, not an empty document.
    def find_page(version, slug, locale: nil)
      effective_pages(version, locale: locale).find do |resolved|
        resolved.slug == slug && !resolved.folder?
      end
    end

    # Previous and next in the flattened reading order, so the theme can render
    # footer navigation without rebuilding the tree. Folders are skipped: a
    # reader stepping forward should land on an article.
    def navigation_for(version, page, locale: nil)
      flat = effective_pages(version, locale: locale).reject(&:folder?)
      index = flat.index { |resolved| resolved.slug == page.slug }

      {
        previous: index && index.positive? ? flat[index - 1] : nil,
        next: index && index < flat.length - 1 ? flat[index + 1] : nil,
      }
    end

    private

    attr_reader :product

    # Newest definition of each slug wins, so walking the chain oldest-first and
    # overwriting gives the inherited value for anything the target version left
    # alone.
    #
    # The newest version that mentions a slug decides its fate even when the row
    # it wrote is unpublished: taking a page down has to beat the version that
    # published it, otherwise the older, still-published row kept winning. That
    # is also why the publish filter runs here instead of inside the per-version
    # query.
    def effective_rows(version, published_only:, locale:)
      chain = chain_for(version)
      rows_by_version = chain.index_with { |source| readable_rows(source, locale: locale) }

      # Where each page sits is decided by `node_key`, not by `parent_id`: a
      # copy in a later version points its parent id at the row in the version
      # it was copied from, which may since have been overridden or deleted.
      node_owner = node_owners(rows_by_version)

      target_id = version.id
      newest = newest_definitions(rows_by_version, published_only: published_only)

      resolved =
        newest.each_with_object({}) do |(slug, (source, page)), result|
          next if published_only && !page.published?

          result[slug] = ResolvedPage.new(
            page,
            inherited_from: (source.id == target_id ? nil : source),
            parent_slug: parent_slug_for(page, node_owner),
          )
        end

      # A folder taken down takes its section with it. Without this, its
      # published children lost their parent from the resolved set and
      # build_tree re-attached them at the top level — taking a folder down
      # published its articles, one level up.
      prune_taken_down_subtrees!(resolved, node_owner) if published_only

      resolved
    end

    # The newest row for every page in the chain, with the version that wrote
    # it. When one version holds the page in two languages the reading one
    # wins; a reader gets a published translation in its place when the one
    # they speak was withdrawn, which is the fallback there was before. The
    # management page edits the language it is looking at, drafts included.
    def newest_definitions(rows_by_version, published_only:)
      definitions = {}

      rows_by_version.each do |source, pages|
        pages.group_by(&:slug).each do |slug, rows|
          chosen = published_only ? (rows.find(&:published?) || rows.first) : rows.first
          definitions[slug] = [source, chosen]
        end
      end

      definitions
    end

    # `node_key` of every page in the chain mapped to its newest definition,
    # published or not. Parent slugs and the "was this section taken down"
    # question both read from here.
    def node_owners(rows_by_version)
      owners = {}

      rows_by_version.each do |_source, pages|
        pages.group_by { |page| node_key_for(page) }.each do |node, rows|
          owners[node] = rows.find(&:published?) || rows.first
        end
      end

      owners
    end

    # A parent that exists but is not published is a section that was
    # withdrawn, not a missing row: readers see none of it. The management page
    # asks for drafts as well (published_only: false), so this only runs for a
    # reader.
    def prune_taken_down_subtrees!(rows, node_owner)
      hidden =
        rows.each_value.filter_map do |resolved|
          parent_node = parent_node_key_for(resolved.page)
          next if parent_node.nil?

          parent = node_owner[parent_node] || resolved.page.parent
          resolved.slug if parent && !parent.published?
        end.to_set

      return if hidden.empty?

      # The children of a hidden row are hidden too, down the whole chain: it
      # is the section that was withdrawn, not one row of it.
      changed = true
      while changed
        changed = false

        rows.each_value do |resolved|
          next if hidden.include?(resolved.slug)
          next unless resolved.parent_slug && hidden.include?(resolved.parent_slug)

          hidden << resolved.slug
          changed = true
        end
      end

      hidden.each { |slug| rows.delete(slug) }
    end

    # A page can be defined in one version while its parent is only defined in
    # an earlier one, so the parent is resolved by node first. The raw
    # association is the fallback for rows written before node keys existed and
    # for a parent that only has a row in the other language.
    def parent_slug_for(page, node_owner)
      parent_node = parent_node_key_for(page)
      return if parent_node.nil?

      (node_owner[parent_node] || page.parent)&.slug
    end

    def parent_node_key_for(page)
      page.parent_node_key.presence ||
        (page.parent_id.present? ? node_key_for(page.parent) : nil)
    end

    # Rows written before the node_key migration (or by a console write that
    # skipped the model) still resolve through their row id.
    def node_key_for(page)
      page.node_key.presence || "page-#{page.id}"
    end

    # The reading language wins over the site default. Both rows for a slug are
    # kept: the caller decides which one stands for the page, so a withdrawn
    # translation can still be replaced by the fallback language.
    def readable_rows(version, locale: nil)
      reading = locale.to_s.presence || I18n.locale.to_s
      fallback = SiteSetting.ingenic_default_locale

      version
        .pages
        .where(locale: [reading, fallback].uniq)
        .to_a
        .sort_by { |page| page.locale == reading ? 0 : 1 }
    end

    # A depth-ordered flat list is enough to render the tree, and it keeps the
    # navigation order and the sidebar order from drifting apart.
    def build_tree(rows)
      children_by_parent = Hash.new { |hash, key| hash[key] = [] }
      rows.each_value { |resolved| children_by_parent[resolved.parent_slug] << resolved }
      children_by_parent.each_value { |list| list.sort_by! { |page| [page.position, page.id] } }

      ordered = []
      seen = {}
      walk(children_by_parent, nil, 0, ordered, seen)

      # A page whose parent is missing from the resolved set is not reachable
      # from the root — the parent may exist only in the other language.
      # Showing the page at the top level beats dropping it silently.
      # Unpublished parents never reach this point: their whole subtree was
      # pruned in effective_rows.
      rows.each_value do |resolved|
        next if seen[resolved.slug]

        resolved.depth = 0
        ordered << resolved
      end

      ordered
    end

    def walk(children_by_parent, parent_slug, depth, ordered, seen)
      children_by_parent[parent_slug].each do |resolved|
        next if seen[resolved.slug]

        seen[resolved.slug] = true
        resolved.depth = depth
        ordered << resolved
        walk(children_by_parent, resolved.slug, depth + 1, ordered, seen)
      end
    end
  end
end
