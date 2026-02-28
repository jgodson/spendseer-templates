#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "csv"
require "digest"
require "fileutils"
require "json"
require "pathname"
require "time"

require_relative "lib/template_catalog"

repo_root = Pathname(__dir__).join("..").expand_path
entries = TemplateCatalog.load_entries!(repo_root)

dist_root = repo_root.join("dist")
site_root = dist_root.join("site")
static_site_root = repo_root.join("site")

FileUtils.rm_rf(dist_root)
FileUtils.mkdir_p(dist_root)
FileUtils.mkdir_p(site_root)
FileUtils.mkdir_p(site_root.join("templates"))

raw_base_url = ENV.fetch("RAW_TEMPLATE_BASE_URL", "").strip
site_base_url = ENV.fetch("SITE_BASE_URL", "").strip
source_base_url = raw_base_url.empty? ? site_base_url : raw_base_url
app_install_base_url = ENV.fetch("APP_INSTALL_BASE_URL", "https://app.spendseer.com").strip

def join_url(base, path)
  normalized_path = path.sub(%r{\A/+}, "")
  return "/#{normalized_path}" if base.nil? || base.empty?

  "#{base.sub(%r{/+\z}, "")}/#{normalized_path}"
end

def h(text)
  CGI.escapeHTML(text.to_s)
end

def safe_markdown_url(url, relative_prefix: nil)
  candidate = url.to_s.strip
  return "#" if candidate.empty?
  return "#" if candidate.match?(/\A(?:javascript|data):/i)
  return candidate if candidate.match?(/\A(?:https?:\/\/|\/|#|mailto:)/i)

  if relative_prefix && !relative_prefix.to_s.strip.empty?
    normalized_prefix = relative_prefix.to_s.sub(%r{\A/+}, "").sub(%r{/+\z}, "")
    return candidate if candidate.start_with?("#{normalized_prefix}/")
    return "#{normalized_prefix}/#{candidate.sub(%r{\A/+}, "")}"
  end

  candidate
end

def markdown_inline_to_html(text, preserve_line_breaks: false, relative_prefix: nil)
  html = h(text.to_s)

  # Code first so other replacements don't process code content.
  html.gsub!(/`([^`]+)`/) { "<code>#{$1}</code>" }

  html.gsub!(/!\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]+)")?\)/) do
    alt = h($1.to_s)
    src = h(safe_markdown_url($2, relative_prefix: relative_prefix))
    title = $3.to_s.strip
    title_attr = title.empty? ? "" : %( title="#{h(title)}")
    %(<img class="note-image" src="#{src}" alt="#{alt}"#{title_attr} loading="lazy" decoding="async" />)
  end

  html.gsub!(/\[([^\]]+)\]\(([^)\s]+)(?:\s+"([^"]+)")?\)/) do
    label = h($1.to_s)
    href = h(safe_markdown_url($2, relative_prefix: relative_prefix))
    title = $3.to_s.strip
    title_attr = title.empty? ? "" : %( title="#{h(title)}")
    %(<a href="#{href}"#{title_attr} target="_blank" rel="noopener noreferrer">#{label}</a>)
  end

  html.gsub!(/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
  html.gsub!(/(?<!\*)\*(?!\s)(.+?)(?<!\s)\*(?!\*)/, "<em>\\1</em>")
  html.gsub!(/\r\n?|\n/, "<br>") if preserve_line_breaks
  html
end

def markdown_table_cells(line)
  stripped = line.to_s.strip
  stripped = stripped.delete_prefix("|").delete_suffix("|")
  stripped.split("|").map { |cell| cell.strip }
end

def markdown_table_divider?(line)
  cells = markdown_table_cells(line)
  return false if cells.empty?

  cells.all? { |cell| cell.match?(/\A:?-{3,}:?\z/) }
end

def markdown_table_line?(line)
  stripped = line.to_s.strip
  !stripped.empty? && stripped.include?("|")
end

def markdown_block_starter?(lines, index)
  line = lines[index].to_s
  stripped = line.strip
  return true if stripped.match?(/\A\#{1,6}\s+\S/)
  return true if stripped.match?(/\A(?:[-*+]\s+|\d+\.\s+)/)
  return true if stripped.start_with?(">")
  return true if (index + 1) < lines.length && markdown_table_line?(line) && markdown_table_divider?(lines[index + 1])

  false
end

def markdown_alignment_style(token)
  case token.to_s.strip
  when /\A:-+\z/
    "left"
  when /\A-+:\z/
    "right"
  when /\A:-+:\z/
    "center"
  else
    nil
  end
end

def render_markdown_table(lines, start_index, relative_prefix: nil)
  header_cells = markdown_table_cells(lines[start_index])
  align_tokens = markdown_table_cells(lines[start_index + 1])
  alignments = align_tokens.map { |token| markdown_alignment_style(token) }

  index = start_index + 2
  body_rows = []
  while index < lines.length
    line = lines[index]
    break unless markdown_table_line?(line)
    break if markdown_table_divider?(line)

    body_rows << markdown_table_cells(line)
    index += 1
  end

  header_html = header_cells.each_with_index.map do |cell, cell_index|
    align = alignments[cell_index]
    align_attr = align.nil? ? "" : %( style="text-align: #{align};")
    "<th#{align_attr}>#{markdown_inline_to_html(cell, relative_prefix: relative_prefix)}</th>"
  end.join

  body_html = body_rows.map do |row|
    cells = (0...header_cells.length).map do |cell_index|
      align = alignments[cell_index]
      align_attr = align.nil? ? "" : %( style="text-align: #{align};")
      "<td#{align_attr}>#{markdown_inline_to_html(row[cell_index].to_s, relative_prefix: relative_prefix)}</td>"
    end.join
    "<tr>#{cells}</tr>"
  end.join

  table_html = <<~HTML
    <table class="note-table">
      <thead><tr>#{header_html}</tr></thead>
      <tbody>#{body_html}</tbody>
    </table>
  HTML

  [table_html.strip, index]
end

def render_markdown_list(lines, start_index, relative_prefix: nil)
  ordered = lines[start_index].to_s.strip.match?(/\A\d+\.\s+/)
  matcher = ordered ? /\A\s*\d+\.\s+(.*)\z/ : /\A\s*[-*+]\s+(.*)\z/
  tag = ordered ? "ol" : "ul"
  items = []
  index = start_index

  while index < lines.length
    line = lines[index]
    break if line.to_s.strip.empty?

    match = line.match(matcher)
    break unless match

    content_lines = [match[1]]
    index += 1
    while index < lines.length
      continuation = lines[index]
      break if continuation.to_s.strip.empty?
      break if continuation.match(matcher)
      break if markdown_block_starter?(lines, index)

      content_lines << continuation.strip
      index += 1
    end

    items << "<li>#{markdown_inline_to_html(content_lines.join(" "), relative_prefix: relative_prefix)}</li>"
  end

  ["<#{tag}>#{items.join}</#{tag}>", index]
end

def render_markdown_blockquote(lines, start_index, relative_prefix: nil)
  quote_lines = []
  index = start_index
  while index < lines.length
    match = lines[index].to_s.match(/\A\s*>\s?(.*)\z/)
    break unless match

    quote_lines << match[1]
    index += 1
  end

  content_html = render_markdown_blocks(quote_lines.join("\n"), relative_prefix: relative_prefix)
  ["<blockquote>#{content_html}</blockquote>", index]
end

def render_markdown_blocks(text, relative_prefix: nil)
  lines = text.to_s.gsub(/\r\n?/, "\n").split("\n")
  fragments = []
  index = 0

  while index < lines.length
    line = lines[index]
    stripped = line.to_s.strip

    if stripped.empty?
      index += 1
      next
    end

    if (heading = stripped.match(/\A(\#{1,6})\s+(.+)\z/))
      level = heading[1].length
      fragments << "<h#{level}>#{markdown_inline_to_html(heading[2], relative_prefix: relative_prefix)}</h#{level}>"
      index += 1
      next
    end

    if (index + 1) < lines.length && markdown_table_line?(line) && markdown_table_divider?(lines[index + 1])
      table_html, next_index = render_markdown_table(lines, index, relative_prefix: relative_prefix)
      fragments << table_html
      index = next_index
      next
    end

    if stripped.match?(/\A(?:[-*+]\s+|\d+\.\s+)/)
      list_html, next_index = render_markdown_list(lines, index, relative_prefix: relative_prefix)
      fragments << list_html
      index = next_index
      next
    end

    if stripped.start_with?(">")
      quote_html, next_index = render_markdown_blockquote(lines, index, relative_prefix: relative_prefix)
      fragments << quote_html
      index = next_index
      next
    end

    paragraph_lines = [stripped]
    index += 1
    while index < lines.length
      break if lines[index].to_s.strip.empty?
      break if markdown_block_starter?(lines, index)

      paragraph_lines << lines[index].strip
      index += 1
    end

    fragments << "<p>#{markdown_inline_to_html(paragraph_lines.join(" "), relative_prefix: relative_prefix)}</p>"
  end

  fragments.join("\n")
end

def render_readme_html(readme_text, relative_prefix: nil)
  content = render_markdown_blocks(readme_text.to_s, relative_prefix: relative_prefix)
  return "" if content.strip.empty?

  %(<section class="note-block readme-block">#{content}</section>)
end

MARKDOWN_IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .gif .webp .svg .avif].freeze

def copy_markdown_image_assets(source_dir:, dist_template_dir:, site_template_dir:)
  Dir.glob(source_dir.join("**", "*").to_s).each do |path|
    next unless File.file?(path)

    ext = File.extname(path).downcase
    next unless MARKDOWN_IMAGE_EXTENSIONS.include?(ext)

    relative_path = Pathname(path).relative_path_from(source_dir)
    dist_target = dist_template_dir.join(relative_path)
    site_target = site_template_dir.join(relative_path)

    FileUtils.mkdir_p(dist_target.dirname)
    FileUtils.mkdir_p(site_target.dirname)
    FileUtils.cp(path, dist_target)
    FileUtils.cp(path, site_target)
  end
end

def metadata_with_source(entry, source_url)
  metadata = TemplateCatalog.deep_stringify_hash(entry.template["metadata"] || {})
  metadata["community_slug"] = entry.slug
  metadata["community_version"] = entry.version
  metadata["source_url"] = source_url
  metadata
end

# Humanize a snake_case field key for display
def humanize_field(key)
  key.to_s.gsub("_", " ").split.map(&:capitalize).join(" ")
end

# Icon emoji per target type
ICONS = {
  "transactions" => "💳",
  "budgets" => "📊"
}.freeze

# Parse a CSV string and return [headers, rows]
def parse_example_csv(csv_text)
  return [[], []] if csv_text.nil? || csv_text.strip.empty?
  table = CSV.parse(csv_text.strip, headers: true)
  [table.headers, table.map(&:fields)]
rescue StandardError
  [[], []]
end

# Render a CSV as an HTML table for inline preview
def render_csv_preview(csv_text)
  headers, rows = parse_example_csv(csv_text)
  return "" if headers.empty?

  th_cells = headers.map { |h_| "<th>#{CGI.escapeHTML(h_.to_s)}</th>" }.join
  tr_rows = rows.map do |row|
    tds = row.map do |cell|
      if cell.nil? || cell.strip.empty?
        "<td><span class=\"csv-empty-cell\">empty</span></td>"
      else
        "<td>#{CGI.escapeHTML(cell.to_s)}</td>"
      end
    end.join
    "<tr>#{tds}</tr>"
  end.join("\n              ")

  <<~HTML
    <div class="csv-preview-wrap">
      <table>
        <thead><tr>#{th_cells}</tr></thead>
        <tbody>
          #{tr_rows}
        </tbody>
      </table>
    </div>
  HTML
end

# Shared nav snippets
NAV_HOME = <<~HTML
  <nav class="site-nav">
    <a class="site-nav__brand" href="index.html">
      <img class="brand-logo" src="assets/spendseer.png?v=BUILD_VERSION" alt="" aria-hidden="true" width="34" height="34" />
      SpendSeer Templates
    </a>
    <div class="site-nav__actions">
      <a class="site-nav__link site-nav__link--app" href="https://app.spendseer.com" target="_blank" rel="noopener noreferrer">Go To App</a>
      <a class="site-nav__link site-nav__link--docs" href="https://docs.spendseer.com" target="_blank" rel="noopener noreferrer">View Docs</a>
    </div>
  </nav>
HTML

NAV_DETAIL = <<~HTML
  <nav class="site-nav">
    <a class="site-nav__brand" href="../../../index.html">
      <img class="brand-logo" src="../../../assets/spendseer.png?v=BUILD_VERSION" alt="" aria-hidden="true" width="34" height="34" />
      SpendSeer Templates
    </a>
    <div class="site-nav__actions">
      <a class="site-nav__back" href="../../../index.html">
        <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
          <path d="M10 3L5 8l5 5"/>
        </svg>
        All templates
      </a>
      <a class="site-nav__link site-nav__link--app" href="https://app.spendseer.com" target="_blank" rel="noopener noreferrer">Go To App</a>
      <a class="site-nav__link site-nav__link--docs" href="https://docs.spendseer.com" target="_blank" rel="noopener noreferrer">View Docs</a>
    </div>
  </nav>
HTML

entries_by_slug = entries.group_by(&:slug)

catalog_templates = entries_by_slug.keys.sort.map do |slug|
  grouped_entries = TemplateCatalog.sort_versions_desc(entries_by_slug.fetch(slug))
  latest_entry = grouped_entries.first
  latest_version = latest_entry.version

  versions = grouped_entries.map do |entry|
    template_json_rel = "templates/#{entry.slug}/#{entry.version}/template.json"
    readme_rel = "templates/#{entry.slug}/#{entry.version}/README.md"
    example_rel = "templates/#{entry.slug}/#{entry.version}/example.csv"

    source_url = join_url(source_base_url, template_json_rel)

    payload = {
      "import_template" => entry.template.merge(
        "metadata" => metadata_with_source(entry, source_url)
      )
    }

    dist_template_dir = dist_root.join("templates", entry.slug, entry.version)
    site_template_dir = site_root.join("templates", entry.slug, entry.version)
    FileUtils.mkdir_p(dist_template_dir)
    FileUtils.mkdir_p(site_template_dir)
    copy_markdown_image_assets(source_dir: entry.source_dir, dist_template_dir: dist_template_dir, site_template_dir: site_template_dir)

    json_body = JSON.pretty_generate(payload)
    template_sha256 = Digest::SHA256.hexdigest(json_body)
    File.write(dist_template_dir.join("template.json"), json_body)
    File.write(site_template_dir.join("template.json"), json_body)

    readme_text = entry.readme
    example_csv = entry.example_csv
    meta_json = JSON.pretty_generate(entry.meta)

    File.write(dist_template_dir.join("README.md"), readme_text)
    File.write(dist_template_dir.join("example.csv"), example_csv)
    File.write(dist_template_dir.join("meta.json"), meta_json)

    File.write(site_template_dir.join("README.md"), readme_text)
    File.write(site_template_dir.join("example.csv"), example_csv)
    File.write(site_template_dir.join("meta.json"), meta_json)

    {
      "version" => entry.version,
      "name" => entry.meta["name"].to_s.strip.empty? ? entry.template["name"] : entry.meta["name"],
      "target_type" => entry.template["target_type"],
      "author" => entry.meta["author"],
      "summary" => entry.meta["summary"],
      "source_url" => source_url,
      "template_sha256" => template_sha256,
      "template_url" => join_url(site_base_url, template_json_rel),
      "readme_url" => join_url(site_base_url, readme_rel),
      "example_csv_url" => join_url(site_base_url, example_rel),
      "details_url" => join_url(site_base_url, "templates/#{entry.slug}/#{entry.version}/"),
      "app_review_url" => "#{app_install_base_url.sub(%r{/+\z}, '')}/community_templates/install/new?slug=#{CGI.escape(entry.slug)}&version=#{CGI.escape(entry.version)}",
      "meta" => entry.meta,
      "import_template" => payload["import_template"],
      "example_csv_text" => example_csv,
      "readme_text" => readme_text
    }
  end

  {
    "slug" => slug,
    "name" => latest_entry.meta["name"].to_s.strip.empty? ? latest_entry.template["name"] : latest_entry.meta["name"],
    "target_type" => latest_entry.template["target_type"],
    "author" => latest_entry.meta["author"],
    "summary" => latest_entry.meta["summary"],
    "latest_version" => latest_version,
    "details_url" => join_url(site_base_url, "templates/#{slug}/"),
    "versions" => versions
  }
end

# Catalog JSON (strip example_csv_text from public catalog)
catalog_for_json = catalog_templates.map do |t|
  t.merge("versions" => t["versions"].map { |v| v.reject { |k, _| k == "example_csv_text" || k == "readme_text" } })
end

catalog = {
  "schema_version" => 1,
  "generated_at" => Time.now.utc.iso8601,
  "templates" => catalog_for_json
}

catalog_json = JSON.pretty_generate(catalog)
File.write(dist_root.join("catalog.json"), catalog_json)
File.write(site_root.join("catalog.json"), catalog_json)

if static_site_root.directory?
  FileUtils.cp_r(static_site_root.children.map(&:to_s), site_root) unless static_site_root.children.empty?
end

# ── Index page ──────────────────────────────────────────────────────────────

index_cards = catalog_templates.map do |template|
  slug = template.fetch("slug")
  target_type = template.fetch("target_type")
  icon = ICONS.fetch(target_type, "📄")
  badge_class = "badge--#{h(target_type)}"
  latest_version = template.fetch("latest_version")

  # Pick install URL from latest version
  install_url = template.fetch("versions").find { |v| v["version"] == latest_version }&.fetch("app_review_url", "#") || "#"
  details_url = "templates/#{slug}/#{latest_version}/"

  <<~HTML
    <article class="card">
      <div class="card__top">
        <span class="card__icon">#{icon}</span>
        <span class="badge #{badge_class}">#{h(target_type)}</span>
      </div>
      <h2><a href="#{h(details_url)}">#{h(template.fetch("name"))}</a></h2>
      <p class="card__desc">#{h(template.fetch("summary").to_s)}</p>
      <div class="card__meta">
        <span class="badge badge--version">Latest #{h(latest_version)}</span>
      </div>
      <div class="card__actions">
        <div class="card__actions-secondary">
          <a class="btn btn--ghost btn--sm" href="#{h(details_url)}">View Details</a>
          <button class="btn btn--ghost btn--sm card-copy-btn" type="button" data-share-url="#{h(details_url)}">Copy Link</button>
        </div>
        <a class="btn btn--primary btn--sm card__install-btn" href="#{h(install_url)}" target="_blank" rel="noopener">
          Install in SpendSeer
          <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
            <path d="M3 8h10M9 4l4 4-4 4"/>
          </svg>
        </a>
      </div>
    </article>
  HTML
end.join("\n")

index_html = <<~HTML
  <!doctype html>
  <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>SpendSeer Community Templates</title>
      <link rel="icon" href="assets/favicon.ico?v=BUILD_VERSION" sizes="any">
      <link rel="icon" href="assets/spendseer.png?v=BUILD_VERSION" type="image/png">
      <link rel="apple-touch-icon" href="assets/apple-touch-icon.png?v=BUILD_VERSION">
      <link rel="stylesheet" href="assets/site.css?v=BUILD_VERSION">
      <script src="assets/catalog-page.js?v=BUILD_VERSION" defer></script>
    </head>
    <body>
      #{NAV_HOME.strip}
      <main class="container">
        <header class="page-header">
          <h1>Community Templates</h1>
          <p>Ready-to-use CSV import templates for SpendSeer — one click to install.</p>
        </header>
      <section class="grid">
        #{index_cards}
      </section>
    </main>
  </body>
</html>
HTML

File.write(site_root.join("index.html"), index_html)

# ── Detail pages ─────────────────────────────────────────────────────────────

catalog_templates.each do |template|
  slug = template.fetch("slug")
  slug_dir = site_root.join("templates", slug)
  FileUtils.mkdir_p(slug_dir)

  target_type = template.fetch("target_type")
  icon = ICONS.fetch(target_type, "📄")
  badge_class = "badge--#{h(target_type)}"
  latest_version = template.fetch("latest_version")
  template["versions"].each do |selected_v|
    selected_version = selected_v.fetch("version")
    selected_version_dir = slug_dir.join(selected_version)
    FileUtils.mkdir_p(selected_version_dir)

    version_options = template["versions"].map do |v|
      selected = v["version"] == selected_version ? " selected" : ""
      "<option value=\"../#{h(v['version'])}/\"#{selected}>#{h(v['version'])}</option>"
    end.join

    field_mappings = selected_v.dig("import_template", "field_mappings") || {}
    mapping_rows = field_mappings.keys.sort.map do |key|
      csv_col = field_mappings[key]
      "<tr><td><code>#{h(csv_col.to_s)}</code></td><td class=\"mapping-arrow\">→</td><td>#{h(humanize_field(key))}</td></tr>"
    end.join("\n              ")

    mapping_tip_html =
      if target_type == "transactions"
        if field_mappings["category_name"].to_s.strip.empty?
          '<div class="mapping-tip"><strong>Tip:</strong> No source category column is mapped. SpendSeer category rules classify transactions from description by default.</div>'
        else
          '<div class="mapping-tip"><strong>Tip:</strong> Source category is mapped. For rows where source category is blank, SpendSeer falls back to description-based category rules.</div>'
        end
      else
        ""
      end

    source_meta = selected_v.dig("meta", "source") || {}
    readme_html = render_readme_html(selected_v["readme_text"])
    csv_preview_html = render_csv_preview(selected_v["example_csv_text"].to_s)

    detail_html = <<~HTML
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>#{h(template.fetch("name"))} | SpendSeer Templates</title>
          <link rel="icon" href="../../../assets/favicon.ico?v=BUILD_VERSION" sizes="any">
          <link rel="icon" href="../../../assets/spendseer.png?v=BUILD_VERSION" type="image/png">
          <link rel="apple-touch-icon" href="../../../assets/apple-touch-icon.png?v=BUILD_VERSION">
          <link rel="stylesheet" href="../../../assets/site.css?v=BUILD_VERSION">
          <script src="../../../assets/template-detail-page.js?v=BUILD_VERSION" defer></script>
        </head>
        <body>
          #{NAV_DETAIL.strip}
          <main class="container detail-layout">
            <section class="detail-shell">
              <!-- Hero / CTA -->
              <section class="hero-cta">
                <div class="hero-cta__header">
                  <div class="hero-cta__main">
                    <div class="hero-cta__badges">
                      <span class="badge #{badge_class}">#{icon} #{h(target_type)}</span>
                      <span class="badge badge--version">#{h(selected_version)}</span>
                    </div>
                    <h1>#{h(template.fetch("name"))}</h1>
                    <p class="hero-cta__summary">#{h(template.fetch("summary").to_s)}</p>
                  </div>
                  <div class="hero-cta__side">
                    <a class="btn btn--primary hero-cta__install" href="#{h(selected_v['app_review_url'] || '#')}" target="_blank" rel="noopener">
                      <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M8 2v10M4 8l4 4 4-4"/><rect x="2" y="12" width="12" height="2" rx="1"/>
                      </svg>
                      Install in SpendSeer
                    </a>
                    <div class="version-selector hero-cta__version">
                      <label for="versionSelect">Version</label>
                      <select id="versionSelect">#{version_options}</select>
                    </div>
                  </div>
                </div>
                <div class="hero-cta__meta">
                  <div class="hero-meta-row">
                    <span class="hero-meta-row__label">Template ID</span>
                    <span class="hero-meta-row__value"><code>#{h(slug)}</code></span>
                  </div>
                  <div class="hero-meta-row">
                    <span class="hero-meta-row__label">Author</span>
                    <span class="hero-meta-row__value">#{h(selected_v['author'].to_s)}</span>
                  </div>
                  <div class="hero-meta-row">
                    <span class="hero-meta-row__label">Template file</span>
                    <span class="hero-meta-row__value"><a href="#{h(selected_v['source_url'] || '#')}" target="_blank" rel="noopener">Open JSON</a></span>
                  </div>
                  <div class="hero-meta-row hero-meta-row--share">
                    <span class="hero-meta-row__label">Share Link</span>
                    <div class="hero-meta-row__value">
                      <div class="copy-snippet hero-copy-snippet">
                        <code id="templateUrlCode">#{h(selected_v['details_url'] || template['details_url'] || '')}</code>
                        <button class="btn btn--ghost btn--sm share-link-btn" id="copyBtn" type="button">Copy</button>
                      </div>
                    </div>
                  </div>
                </div>
                <div class="hero-cta__actions">
                  <a class="btn btn--ghost" href="#csvPreviewPanel">View Example CSV</a>
                  <a class="btn btn--ghost" href="#mappingPanel">View Column Mappings</a>
                  <a class="btn btn--ghost" href="#setupNotesPanel">View Export Instructions</a>
                </div>
              </section>

              <section class="detail-inner-grid">
                <!-- Where to export -->
                <div class="panel panel--full" id="exportPanel">
                  <div class="panel__header">
                    <h2>Where to export</h2>
                  </div>
                  <div class="field-list" id="exportDetails">
                    <div class="field-row">
                      <span class="field-row__label">Institution</span>
                      <span class="field-row__value">#{h(source_meta['institution'].to_s)}</span>
                    </div>
                    <div class="field-row">
                      <span class="field-row__label">Export path</span>
                      <span class="field-row__value">#{h(source_meta['csv_export_path'].to_s)}</span>
                    </div>
                  </div>
                </div>

                <!-- Export instructions -->
                <div class="panel panel--full" id="setupNotesPanel">
                  <div class="panel__header">
                    <h2>Export Instructions</h2>
                  </div>
                  <div class="panel__body notes-content">
                    #{readme_html}
                  </div>
                </div>

                <!-- Column mapping -->
                <div class="panel panel--full" id="mappingPanel">
                  <div class="panel__header">
                    <h2>Column mapping</h2>
                  </div>
                  <div class="panel__body--flush">
                    <table>
                      <thead>
                        <tr>
                          <th>Your CSV column</th>
                          <th></th>
                          <th>SpendSeer field</th>
                        </tr>
                      </thead>
                      <tbody>
                        #{mapping_rows}
                      </tbody>
                    </table>
                    #{mapping_tip_html}
                  </div>
                </div>

                <!-- Example CSV preview -->
                <div class="panel panel--full" id="csvPreviewPanel">
                  <div class="panel__header">
                    <h2>Example CSV</h2>
                    <a class="btn btn--ghost btn--sm" href="#{h(selected_v['example_csv_url'] || '#')}" download="#{h("#{slug}-#{selected_version}-example.csv")}">Download</a>
                  </div>
                  <div class="panel__body--flush">
                    #{csv_preview_html}
                  </div>
                </div>
              </section>
            </section>
          </main>
        </body>
      </html>
    HTML

    File.write(selected_version_dir.join("index.html"), detail_html)
  end

  latest_redirect = "#{latest_version}/"
  latest_redirect_html = <<~HTML
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="refresh" content="0;url=#{h(latest_redirect)}">
        <link rel="canonical" href="#{h(latest_redirect)}">
        <title>Redirecting…</title>
      </head>
      <body>
        <p>Redirecting to <a href="#{h(latest_redirect)}">latest template version</a>.</p>
      </body>
    </html>
  HTML
  File.write(slug_dir.join("index.html"), latest_redirect_html)
end

puts "Built #{catalog_templates.size} templates (#{entries.size} versions)."
puts "Wrote #{dist_root.join('catalog.json').relative_path_from(repo_root)}"
puts "Wrote #{site_root.join('index.html').relative_path_from(repo_root)}"
