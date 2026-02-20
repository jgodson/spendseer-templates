#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"
require_relative "lib/template_catalog"

repo_root = Pathname(__dir__).join("..").expand_path
entries = TemplateCatalog.load_entries!(repo_root)

groups = entries.group_by(&:slug)
duplicates = groups.select { |_slug, versions| versions.map(&:version).uniq.size != versions.size }

if duplicates.any?
  duplicates.each do |slug, versions|
    warn "Duplicate versions for slug #{slug}: #{versions.map(&:version).join(', ')}"
  end
  exit 1
end

puts "Validated #{groups.size} template slugs (#{entries.size} versions)."
