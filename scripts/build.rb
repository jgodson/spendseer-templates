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
    <a class="site-nav__brand" href="../../index.html">
      <img class="brand-logo" src="../../assets/spendseer.png?v=BUILD_VERSION" alt="" aria-hidden="true" width="34" height="34" />
      SpendSeer Templates
    </a>
    <div class="site-nav__actions">
      <a class="site-nav__back" href="../../index.html">
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

FOOTER_HOME = <<~HTML
  <footer class="site-footer">
    <a class="catalog-link" href="catalog.json" target="_blank" rel="noopener">
      <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M1.5 8s2.3-4 6.5-4 6.5 4 6.5 4-2.3 4-6.5 4-6.5-4-6.5-4z"/>
        <circle cx="8" cy="8" r="2.1"/>
      </svg>
      View catalog.json
    </a>
  </footer>
HTML

FOOTER_DETAIL = <<~HTML
  <footer class="site-footer">
    <a class="catalog-link" href="../../catalog.json" target="_blank" rel="noopener">
      <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M1.5 8s2.3-4 6.5-4 6.5 4 6.5 4-2.3 4-6.5 4-6.5-4-6.5-4z"/>
        <circle cx="8" cy="8" r="2.1"/>
      </svg>
      View catalog.json
    </a>
  </footer>
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
      "details_url" => join_url(site_base_url, "templates/#{entry.slug}/"),
      "app_review_url" => "#{app_install_base_url.sub(%r{/+\z}, '')}/community_templates/install/new?slug=#{CGI.escape(entry.slug)}&version=#{CGI.escape(entry.version)}",
      "meta" => entry.meta,
      "import_template" => payload["import_template"],
      "example_csv_text" => example_csv
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
  t.merge("versions" => t["versions"].map { |v| v.reject { |k, _| k == "example_csv_text" } })
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
  details_url = "templates/#{h(slug)}/"

  <<~HTML
    <article class="card">
      <div class="card__top">
        <span class="card__icon">#{icon}</span>
        <span class="badge #{badge_class}">#{h(target_type)}</span>
      </div>
      <h2><a href="#{details_url}">#{h(template.fetch("name"))}</a></h2>
      <p class="card__desc">#{h(template.fetch("summary").to_s)}</p>
      <div class="card__footer">
        <span class="badge badge--version">#{h(latest_version)}</span>
        <a class="btn btn--primary btn--sm" href="#{h(install_url)}" target="_blank" rel="noopener">
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
      <link rel="apple-touch-icon" href="assets/apple-touch-icon.png?v=BUILD_VERSION">
      <link rel="stylesheet" href="assets/site.css?v=BUILD_VERSION">
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
      #{FOOTER_HOME.strip}
    </body>
  </html>
HTML

File.write(site_root.join("index.html"), index_html)

# ── Detail pages ─────────────────────────────────────────────────────────────

catalog_templates.each do |template|
  slug = template.fetch("slug")
  slug_dir = site_root.join("templates", slug)
  FileUtils.mkdir_p(slug_dir)

  # Embed template data (strip example_csv_text from JS payload)
  payload_for_js = template.merge(
    "versions" => template["versions"].map { |v| v.reject { |k, _| k == "example_csv_text" } }
  )
  payload_js = JSON.generate(payload_for_js)

  target_type = template.fetch("target_type")
  icon = ICONS.fetch(target_type, "📄")
  badge_class = "badge--#{h(target_type)}"
  latest_version = template.fetch("latest_version")
  latest_v = template["versions"].find { |v| v["version"] == latest_version } || template["versions"].first

  # Build version option tags (server-rendered so page works without JS for basics)
  version_options = template["versions"].map do |v|
    selected = v["version"] == latest_version ? " selected" : ""
    "<option value=\"#{h(v['version'])}\"#{selected}>#{h(v['version'])}</option>"
  end.join

  # Build the initial field mapping rows (server-rendered for latest version)
  field_mappings = latest_v.dig("import_template", "field_mappings") || {}
  mapping_rows = field_mappings.keys.sort.map do |key|
    csv_col = field_mappings[key]
    "<tr><td><code>#{h(csv_col.to_s)}</code></td><td class=\"mapping-arrow\">→</td><td>#{h(humanize_field(key))}</td></tr>"
  end.join("\n              ")

  mapping_tip_html =
    if target_type == "transactions"
      '<div class="mapping-tip"><strong>Tip:</strong> Leave <code>Category</code> blank in your CSV so SpendSeer category rules can auto-match.</div>'
    else
      ""
    end

  # Source meta from latest version
  source_meta = latest_v.dig("meta", "source") || {}
  source_notes = Array(source_meta["notes"] || [])
  notes_html = source_notes.map { |note| "<li>#{h(note)}</li>" }.join("\n              ")

  # CSV preview for latest version
  csv_preview_html = render_csv_preview(latest_v["example_csv_text"].to_s)

  detail_html = <<~HTML
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{h(template.fetch("name"))} | SpendSeer Templates</title>
        <link rel="icon" href="../../assets/favicon.ico?v=BUILD_VERSION" sizes="any">
        <link rel="apple-touch-icon" href="../../assets/apple-touch-icon.png?v=BUILD_VERSION">
        <link rel="stylesheet" href="../../assets/site.css?v=BUILD_VERSION">
      </head>
      <body>
        #{NAV_DETAIL.strip}
        <main class="container detail-layout">

          <!-- Hero / CTA -->
          <section class="hero-cta">
            <div class="hero-cta__badges">
              <span class="badge #{badge_class}">#{icon} #{h(target_type)}</span>
              <span class="badge badge--version" id="heroBadgeVersion">#{h(latest_version)}</span>
            </div>
            <h1>#{h(template.fetch("name"))}</h1>
            <p class="hero-cta__summary">#{h(template.fetch("summary").to_s)}</p>
            <div class="hero-cta__actions">
              <a class="btn btn--primary" id="installBtn" href="#{h(latest_v['app_review_url'] || '#')}" target="_blank" rel="noopener">
                <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                  <path d="M8 2v10M4 8l4 4 4-4"/><rect x="2" y="12" width="12" height="2" rx="1"/>
                </svg>
                Install in SpendSeer
              </a>
              <a class="btn btn--ghost" id="exampleBtn" href="#csvPreviewPanel">View Example CSV</a>
              <a class="btn btn--ghost" id="readmeBtn" href="#exportPanel">View Setup Notes</a>
            </div>
          </section>

          <!-- Template URL -->
          <div class="panel">
            <div class="panel__header">
              <h2>Template URL</h2>
            </div>
            <div class="panel__body">
              <div class="copy-snippet" id="templateUrlSnippet">
                <code id="templateUrlCode">#{h(latest_v['source_url'] || '')}</code>
                <button class="copy-btn" id="copyBtn" type="button">
                  <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="12" height="12">
                    <rect x="5" y="5" width="9" height="9" rx="1.5"/><path d="M3 11H2a1 1 0 01-1-1V2a1 1 0 011-1h8a1 1 0 011 1v1"/>
                  </svg>
                  Copy
                </button>
              </div>
            </div>
          </div>

          <!-- Version selector -->
          <div class="panel">
            <div class="panel__header">
              <h2>Version</h2>
              <div class="version-selector">
                <label for="versionSelect">Select version</label>
                <select id="versionSelect">#{version_options}</select>
              </div>
            </div>
          </div>

          <!-- Column mapping -->
          <div class="panel">
            <div class="panel__header">
              <h2>Column mapping</h2>
            </div>
            <div class="panel__body--flush">
              <table id="mappingTable">
                <thead>
                  <tr>
                    <th>Your CSV column</th>
                    <th></th>
                    <th>SpendSeer field</th>
                  </tr>
                </thead>
                <tbody id="mappingRows">
                  #{mapping_rows}
                </tbody>
              </table>
              #{mapping_tip_html}
            </div>
          </div>

          <!-- Example CSV preview -->
          <div class="panel" id="csvPreviewPanel">
            <div class="panel__header">
              <h2>Example CSV</h2>
              <a class="btn btn--ghost btn--sm" id="exampleDownloadBtn" href="#{h(latest_v['example_csv_url'] || '#')}" download="#{h("#{slug}-#{latest_version}-example.csv")}">Download</a>
            </div>
            <div class="panel__body--flush" id="csvPreviewBody">
              #{csv_preview_html}
            </div>
          </div>

          <!-- Where to export -->
          <div class="panel" id="exportPanel">
            <div class="panel__header">
              <h2>Where to export</h2>
            </div>
            <div class="field-list" id="exportDetails">
              <div class="field-row">
                <span class="field-row__label">Institution</span>
                <span class="field-row__value" id="sourceInstitution">#{h(source_meta['institution'].to_s)}</span>
              </div>
              <div class="field-row">
                <span class="field-row__label">Export path</span>
                <span class="field-row__value" id="sourcePath">#{h(source_meta['csv_export_path'].to_s)}</span>
              </div>
            </div>
            <ul class="notes-list" id="sourceNotes">
              #{notes_html}
            </ul>
          </div>

          <!-- Template details / metadata -->
          <div class="panel">
            <div class="panel__header">
              <h2>Details</h2>
            </div>
            <div class="field-list">
              <div class="field-row">
                <span class="field-row__label">Template ID</span>
                <span class="field-row__value"><code>#{h(slug)}</code></span>
              </div>
              <div class="field-row">
                <span class="field-row__label">Author</span>
                <span class="field-row__value" id="detailAuthor">#{h(latest_v['author'].to_s)}</span>
              </div>
              <div class="field-row">
                <span class="field-row__label">Version</span>
                <span class="field-row__value"><code id="detailVersion">#{h(latest_version)}</code></span>
              </div>
              <div class="field-row">
                <span class="field-row__label">Template file</span>
                <span class="field-row__value"><a id="templateJsonLink" href="#{h(latest_v['source_url'] || '#')}" target="_blank" rel="noopener">Open JSON</a></span>
              </div>
            </div>
          </div>

        </main>
        #{FOOTER_DETAIL.strip}

        <script>
          const TEMPLATE = #{payload_js};

          const versionSelect = document.getElementById("versionSelect");
          const heroBadgeVersion = document.getElementById("heroBadgeVersion");
          const installBtn = document.getElementById("installBtn");
          const exampleBtn = document.getElementById("exampleBtn");
          const readmeBtn = document.getElementById("readmeBtn");
          const exampleDownloadBtn = document.getElementById("exampleDownloadBtn");
          const mappingRows = document.getElementById("mappingRows");
          const sourceInstitution = document.getElementById("sourceInstitution");
          const sourcePath = document.getElementById("sourcePath");
          const sourceNotes = document.getElementById("sourceNotes");
          const detailAuthor = document.getElementById("detailAuthor");
          const detailVersion = document.getElementById("detailVersion");
          const templateUrlCode = document.getElementById("templateUrlCode");
          const templateJsonLink = document.getElementById("templateJsonLink");
          const copyBtn = document.getElementById("copyBtn");

          function humanizeKey(key) {
            return key.replace(/_/g, " ").replace(/\\b\\w/g, c => c.toUpperCase());
          }

          function toAbsoluteUrl(url) {
            if (!url) return "";
            try {
              return new URL(url, window.location.origin).toString();
            } catch (_error) {
              return url;
            }
          }

          function setLinks(details) {
            installBtn.href = details.app_review_url || "#";
            exampleDownloadBtn.href = details.example_csv_url || "#";
            exampleDownloadBtn.download = (TEMPLATE.slug || "template") + "-" + (details.version || "latest") + "-example.csv";
            const shareableSourceUrl = toAbsoluteUrl(details.source_url || "");
            templateJsonLink.href = shareableSourceUrl || "#";
            templateUrlCode.textContent = shareableSourceUrl;
          }

          function renderMappings(details) {
            mappingRows.innerHTML = "";
            const mappings = (details.import_template && details.import_template.field_mappings) || {};
            Object.keys(mappings).sort().forEach((key) => {
              const tr = document.createElement("tr");
              tr.innerHTML =
                "<td><code>" + mappings[key] + "</code></td>" +
                "<td class=\\"mapping-arrow\\">→</td>" +
                "<td>" + humanizeKey(key) + "</td>";
              mappingRows.appendChild(tr);
            });
          }

          function renderSource(details) {
            const src = (details.meta && details.meta.source) || {};
            sourceInstitution.textContent = src.institution || "";
            sourcePath.textContent = src.csv_export_path || "";
            sourceNotes.innerHTML = "";
            (src.notes || []).forEach((note) => {
              const li = document.createElement("li");
              li.textContent = note;
              sourceNotes.appendChild(li);
            });
          }

          function render(selectedVersion) {
            const details = TEMPLATE.versions.find((v) => v.version === selectedVersion) || TEMPLATE.versions[0];
            if (!details) return;

            heroBadgeVersion.textContent = details.version;
            detailAuthor.textContent = details.author || "Unknown";
            detailVersion.textContent = details.version;
            setLinks(details);
            renderMappings(details);
            renderSource(details);
          }

          versionSelect.addEventListener("change", (e) => render(e.target.value));
          render(TEMPLATE.latest_version);

          // Copy button
          copyBtn.addEventListener("click", () => {
            const text = templateUrlCode.textContent;
            if (!text) return;
            navigator.clipboard.writeText(text).then(() => {
              copyBtn.classList.add("copied");
              copyBtn.textContent = "Copied!";
              setTimeout(() => {
                copyBtn.classList.remove("copied");
                copyBtn.innerHTML = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" width="12" height="12"><rect x="5" y="5" width="9" height="9" rx="1.5"/><path d="M3 11H2a1 1 0 01-1-1V2a1 1 0 011-1h8a1 1 0 011 1v1"/></svg> Copy';
              }, 2000);
            });
          });
        </script>
      </body>
    </html>
  HTML

  File.write(slug_dir.join("index.html"), detail_html)
end

puts "Built #{catalog_templates.size} templates (#{entries.size} versions)."
puts "Wrote #{dist_root.join('catalog.json').relative_path_from(repo_root)}"
puts "Wrote #{site_root.join('index.html').relative_path_from(repo_root)}"
