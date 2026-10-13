# frozen_string_literal: true

module Ingenic
  # The "tell us about yourself" form, as configured.
  #
  # The fields are a site setting rather than a fixed list because the Chinese
  # forum's form is the template and it will keep changing. Reading them through
  # one place means the form the visitor sees, the validation on submit and the
  # admin's view of an answer all come from the same definition.
  module DeveloperForm
    FALLBACK = [
      { "key" => "full_name", "label" => "Full name", "type" => "text", "required" => true },
      { "key" => "company", "label" => "Company", "type" => "text", "required" => true },
      { "key" => "job_title", "label" => "Job title", "type" => "text", "required" => false },
      {
        "key" => "country",
        "label" => "Country or region",
        "type" => "text",
        "required" => true,
      },
      { "key" => "contact_email", "label" => "Contact email", "type" => "text", "required" => true },
      { "key" => "phone", "label" => "Phone", "type" => "text", "required" => false },
      { "key" => "use_case", "label" => "Intended use", "type" => "textarea", "required" => true },
      { "key" => "project_stage", "label" => "Project stage", "type" => "text", "required" => false },
      {
        "key" => "estimated_volume",
        "label" => "Estimated annual volume",
        "type" => "text",
        "required" => false,
      },
      { "key" => "notes", "label" => "Anything else", "type" => "textarea", "required" => false },
    ].freeze

    TYPES = %w[text textarea].freeze

    module_function

    def fields
      configured = parse(SiteSetting.ingenic_developer_form_fields)
      return configured if configured.present?

      FALLBACK.map { |field| field.transform_keys(&:to_sym) }
    end

    def required_keys
      fields.select { |field| field[:required] }.map { |field| field[:key].to_s }
    end

    # Answers are stored as a document, so what comes back from a request has to
    # be reduced to exactly the configured fields. Without this a visitor could
    # post arbitrary keys into the profile and an admin would later read them
    # back as if the form had asked for them.
    def normalize(params)
      submitted = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : (params || {})

      fields.each_with_object({}) do |field, result|
        key = field[:key].to_s
        raw = submitted[key] || submitted[key.to_sym]
        result[key] = raw.is_a?(String) ? raw.strip.first(2000) : nil
      end
    end

    def errors_for(data)
      required_keys.filter_map do |key|
        field = fields.find { |candidate| candidate[:key].to_s == key }
        next if data[key].present?

        I18n.t("ingenic.developer_form.missing", field: field[:label])
      end
    end

    def parse(raw)
      return [] if raw.blank?

      parsed = JSON.parse(raw.to_s)
      return [] unless parsed.is_a?(Array)

      parsed.filter_map do |entry|
        next unless entry.is_a?(Hash)

        key = entry["key"].to_s.strip
        label = entry["label"].to_s.strip
        next if key.blank? || label.blank?

        type = TYPES.include?(entry["type"].to_s) ? entry["type"].to_s : "text"
        { key: key, label: label, type: type.to_sym, required: entry["required"] == true }
      end
    rescue JSON::ParserError
      []
    end
  end
end
