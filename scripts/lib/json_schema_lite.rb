# frozen_string_literal: true

module JsonSchemaLite
  module_function

  def validate(instance, schema, path: "$")
    errors = []
    schema = normalize_hash(schema)
    instance = normalize_value(instance)

    errors.concat(validate_type(instance, schema, path))
    return errors if errors.any? && schema["type"].to_s != "object"

    errors.concat(validate_object(instance, schema, path)) if schema["type"].to_s == "object" && instance.is_a?(Hash)
    errors.concat(validate_array(instance, schema, path)) if schema["type"].to_s == "array" && instance.is_a?(Array)
    errors.concat(validate_string(instance, schema, path)) if instance.is_a?(String)
    errors.concat(validate_numeric_bounds(instance, schema, path))
    errors.concat(validate_enum_const(instance, schema, path))

    errors
  end

  def normalize_hash(value)
    value.is_a?(Hash) ? value.transform_keys(&:to_s) : {}
  end

  def normalize_value(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested), memo|
        memo[key.to_s] = normalize_value(nested)
      end
    when Array
      value.map { |nested| normalize_value(nested) }
    else
      value
    end
  end

  def validate_type(instance, schema, path)
    expected_type = schema["type"].to_s
    return [] if expected_type.empty?

    valid = case expected_type
    when "object" then instance.is_a?(Hash)
    when "array" then instance.is_a?(Array)
    when "string" then instance.is_a?(String)
    when "integer" then instance.is_a?(Integer)
    when "number" then instance.is_a?(Numeric)
    when "boolean" then instance == true || instance == false
    else true
    end

    valid ? [] : ["#{path}: expected type #{expected_type}, got #{instance.class}"]
  end

  def validate_object(instance, schema, path)
    errors = []
    required = Array(schema["required"]).map(&:to_s)
    properties = normalize_hash(schema["properties"])

    required.each do |required_key|
      errors << "#{path}: missing required property '#{required_key}'" unless instance.key?(required_key)
    end

    additional_properties = schema.fetch("additionalProperties", true)
    unless additional_properties
      unknown_keys = instance.keys - properties.keys
      unknown_keys.each { |key| errors << "#{path}: unknown property '#{key}'" }
    end

    min_properties = schema["minProperties"]
    if min_properties.is_a?(Numeric) && instance.size < min_properties.to_i
      errors << "#{path}: expected at least #{min_properties.to_i} properties"
    end

    instance.each do |key, value|
      property_schema = properties[key]
      next unless property_schema.is_a?(Hash)

      child_path = "#{path}.#{key}"
      errors.concat(validate(value, property_schema, path: child_path))
    end

    errors
  end

  def validate_array(instance, schema, path)
    errors = []

    items_schema = schema["items"]
    if items_schema.is_a?(Hash)
      instance.each_with_index do |value, index|
        errors.concat(validate(value, items_schema, path: "#{path}[#{index}]"))
      end
    end

    errors
  end

  def validate_string(instance, schema, path)
    errors = []

    min_length = schema["minLength"]
    if min_length.is_a?(Numeric) && instance.length < min_length.to_i
      errors << "#{path}: must have minimum length #{min_length.to_i}"
    end

    pattern = schema["pattern"].to_s
    unless pattern.empty?
      regex = Regexp.new(pattern)
      errors << "#{path}: does not match pattern #{pattern}" unless regex.match?(instance)
    end

    errors
  rescue RegexpError => e
    ["#{path}: invalid schema pattern '#{pattern}' (#{e.class})"]
  end

  def validate_numeric_bounds(instance, schema, path)
    errors = []
    return errors unless instance.is_a?(Numeric)

    minimum = schema["minimum"]
    if minimum.is_a?(Numeric) && instance < minimum
      errors << "#{path}: must be >= #{minimum}"
    end

    maximum = schema["maximum"]
    if maximum.is_a?(Numeric) && instance > maximum
      errors << "#{path}: must be <= #{maximum}"
    end

    errors
  end

  def validate_enum_const(instance, schema, path)
    errors = []

    if schema.key?("const") && instance != schema["const"]
      errors << "#{path}: must be #{schema['const'].inspect}"
    end

    if schema["enum"].is_a?(Array) && !schema["enum"].include?(instance)
      errors << "#{path}: must be one of #{schema['enum'].inspect}"
    end

    errors
  end
end
