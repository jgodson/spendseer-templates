# frozen_string_literal: true

require "pathname"
require "yaml"
require "csv"
require "json"
require_relative "json_schema_lite"

module TemplateCatalog
  class CatalogError < StandardError; end

  Entry = Struct.new(
    :slug,
    :version,
    :meta,
    :template,
    :readme,
    :example_csv,
    :source_dir,
    keyword_init: true
  )

  SLUG_REGEX = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  VERSION_REGEX = /\Av\d+(?:\.\d+){0,2}\z/
  TARGET_TYPES = %w[transactions budgets].freeze
  CATEGORY_TYPES = %w[income expense savings].freeze
  SUPPORTED_AMOUNT_SIGNS = %w[as_is absolute negate].freeze

  module_function

  def load_entries!(repo_root)
    root = Pathname(repo_root).expand_path
    templates_root = root.join("templates")
    schemas_root = root.join("schemas")
    raise CatalogError, "Missing templates/ directory" unless templates_root.directory?
    raise CatalogError, "Missing schemas/ directory" unless schemas_root.directory?

    meta_schema = load_schema!(schemas_root.join("meta.schema.json"), schema_name: "meta")
    template_schema = load_schema!(schemas_root.join("template.schema.json"), schema_name: "template")

    errors = []
    entries = []

    slug_dirs = templates_root.children.select(&:directory?).sort_by(&:basename)
    slug_dirs.each do |slug_dir|
      slug = slug_dir.basename.to_s
      errors << "Invalid slug '#{slug}'" unless valid_slug?(slug)

      version_dirs = slug_dir.children.select(&:directory?).sort_by(&:basename)
      if version_dirs.empty?
        errors << "#{slug_dir.relative_path_from(root)} has no version directories"
        next
      end

      version_dirs.each do |version_dir|
        version = version_dir.basename.to_s
        errors << "Invalid version '#{version}' at #{version_dir.relative_path_from(root)}" unless valid_version?(version)

        required = %w[meta.yml template.yml README.md example.csv]
        missing = required.reject { |name| version_dir.join(name).file? }
        unless missing.empty?
          errors << "Missing #{missing.join(', ')} in #{version_dir.relative_path_from(root)}"
          next
        end

        begin
          meta = deep_stringify_hash(YAML.safe_load(version_dir.join("meta.yml").read, aliases: true) || {})
          template_root = deep_stringify_hash(YAML.safe_load(version_dir.join("template.yml").read, aliases: true) || {})
        rescue StandardError => e
          errors << "YAML parse error in #{version_dir.relative_path_from(root)}: #{e.class}"
          next
        end

        validate_schema(errors, target_path: version_dir.relative_path_from(root), schema: meta_schema, payload: meta, context: "meta.yml")
        validate_schema(errors, target_path: version_dir.relative_path_from(root), schema: template_schema, payload: template_root, context: "template.yml")

        import_template = normalize_template(template_root)
        readme = version_dir.join("README.md").read
        example_csv = version_dir.join("example.csv").read

        validate_entry(errors, root, slug, version, version_dir, meta, import_template, example_csv)

        entries << Entry.new(
          slug: slug,
          version: version,
          meta: meta,
          template: import_template,
          readme: readme,
          example_csv: example_csv,
          source_dir: version_dir
        )
      end
    end

    raise CatalogError, errors.join("\n") unless errors.empty?

    entries
  end

  def latest_version(entries)
    entries.max_by { |entry| version_parts(entry.version) }&.version
  end

  def sort_versions_desc(entries)
    entries.sort_by { |entry| version_parts(entry.version) }.reverse
  end

  def version_parts(raw)
    normalized = raw.to_s.delete_prefix("v")
    parts = normalized.split(".").map { |part| Integer(part, 10) }
    [parts[0] || 0, parts[1] || 0, parts[2] || 0]
  rescue ArgumentError
    [0, 0, 0]
  end

  def valid_slug?(slug)
    SLUG_REGEX.match?(slug)
  end

  def valid_version?(version)
    VERSION_REGEX.match?(version)
  end

  def normalize_template(raw)
    payload = if raw["import_template"].is_a?(Hash)
      raw["import_template"]
    elsif raw["template"].is_a?(Hash)
      raw["template"]
    elsif raw.is_a?(Hash)
      raw
    else
      {}
    end

    deep_stringify_hash(payload)
  end

  def deep_stringify_hash(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested_value), memo|
        memo[key.to_s] = deep_stringify_hash(nested_value)
      end
    when Array
      value.map { |nested| deep_stringify_hash(nested) }
    else
      value
    end
  end

  def validate_entry(errors, root, slug, version, version_dir, meta, template, example_csv)
    relative = version_dir.relative_path_from(root)

    errors << "#{relative}: meta.yml slug must be '#{slug}'" unless meta["slug"].to_s.strip == slug
    errors << "#{relative}: meta.yml version must be '#{version}'" unless meta["version"].to_s.strip == version

    name = template["name"].to_s.strip
    target_type = template["target_type"].to_s.strip
    source_type = template["source_type"].to_s.strip
    metadata = deep_stringify_hash(template["metadata"] || {})

    errors << "#{relative}: template name is required" if name.empty?
    errors << "#{relative}: target_type must be one of #{TARGET_TYPES.join(', ')}" unless TARGET_TYPES.include?(target_type)
    errors << "#{relative}: source_type must be csv" unless source_type == "csv"

    errors << "#{relative}: metadata.community_slug must be '#{slug}'" unless metadata["community_slug"].to_s.strip == slug
    errors << "#{relative}: metadata.community_version must be '#{version}'" unless metadata["community_version"].to_s.strip == version

    field_mappings = template["field_mappings"]
    errors << "#{relative}: field_mappings must be an object" unless field_mappings.is_a?(Hash)

    required_mapping_keys =
      if target_type == "budgets"
        %w[year amount category_name]
      else
        %w[date description amount category_name]
      end

    required_mapping_keys.each do |key|
      errors << "#{relative}: field_mappings.#{key} is required" if field_mappings.to_h[key].to_s.strip.empty?
    end

    validate_template_compatibility(errors, relative: relative, template: template, example_csv: example_csv)
  end

  def validate_template_compatibility(errors, relative:, template:, example_csv:)
    field_mappings = normalize_hash(template["field_mappings"])
    mapped_columns = field_mappings.values.map { |value| value.to_s.strip }.reject(&:empty?)
    duplicates = mapped_columns.group_by(&:itself).select { |_value, occurrences| occurrences.size > 1 }.keys
    unless duplicates.empty?
      errors << "#{relative}: field_mappings map multiple fields to the same source column: #{duplicates.join(', ')}"
    end

    csv_options = normalize_hash(template["csv_options"])
    delimiter = csv_options["delimiter"].to_s
    if !delimiter.empty? && delimiter.length != 1
      errors << "#{relative}: csv_options.delimiter must be a single character"
    end
    quote_char = csv_options["quote_char"].to_s
    if !quote_char.empty? && quote_char.length != 1
      errors << "#{relative}: csv_options.quote_char must be a single character"
    end

    transform_rules = normalize_hash(template["transform_rules"])
    amount_sign = transform_rules["amount_sign"].to_s.strip
    if !amount_sign.empty? && !SUPPORTED_AMOUNT_SIGNS.include?(amount_sign)
      errors << "#{relative}: transform_rules.amount_sign must be one of #{SUPPORTED_AMOUNT_SIGNS.join(', ')}"
    end
    category_type_default = transform_rules["category_type_default"].to_s.strip
    if !category_type_default.empty? && !CATEGORY_TYPES.include?(category_type_default)
      errors << "#{relative}: transform_rules.category_type_default must be one of #{CATEGORY_TYPES.join(', ')}"
    end

    metadata = normalize_hash(template["metadata"])
    slug = metadata["community_slug"].to_s.strip
    version = metadata["community_version"].to_s.strip
    if slug.length > 120
      errors << "#{relative}: metadata.community_slug exceeds 120 characters"
    end
    if version.length > 60
      errors << "#{relative}: metadata.community_version exceeds 60 characters"
    end
    source_url = metadata["source_url"].to_s.strip
    if !source_url.empty? && !(source_url.start_with?("http://") || source_url.start_with?("https://"))
      errors << "#{relative}: metadata.source_url must be an HTTP(S) URL when present"
    end

    validate_example_csv(errors, relative: relative, template: template, example_csv: example_csv)
  end

  def validate_example_csv(errors, relative:, template:, example_csv:)
    csv = CSV.parse(example_csv.to_s, headers: true)
    headers = Array(csv.headers).map { |header| header.to_s.strip }.reject(&:empty?)
    if headers.empty?
      errors << "#{relative}: example.csv must include a header row"
      return
    end

    field_mappings = normalize_hash(template["field_mappings"])
    required_fields =
      if template["target_type"].to_s == "budgets"
        %w[year amount category_name]
      else
        %w[date description amount category_name]
      end

    required_fields.each do |field|
      mapped_column = field_mappings[field].to_s.strip
      next if mapped_column.empty?
      next if headers.include?(mapped_column)

      errors << "#{relative}: example.csv is missing mapped column '#{mapped_column}' for field '#{field}'"
    end
  rescue CSV::MalformedCSVError => e
    errors << "#{relative}: example.csv is invalid CSV (#{e.class})"
  end

  def validate_schema(errors, target_path:, schema:, payload:, context:)
    schema_errors = JsonSchemaLite.validate(payload, schema, path: context)
    schema_errors.each do |error_message|
      errors << "#{target_path}: #{error_message}"
    end
  end

  def load_schema!(schema_path, schema_name:)
    payload = JSON.parse(schema_path.read)
    deep_stringify_hash(payload)
  rescue Errno::ENOENT
    raise CatalogError, "Missing #{schema_name} schema at #{schema_path}"
  rescue JSON::ParserError => e
    raise CatalogError, "Invalid #{schema_name} schema JSON at #{schema_path}: #{e.class}"
  end

  def normalize_hash(value)
    value.is_a?(Hash) ? value.transform_keys(&:to_s) : {}
  end
end
