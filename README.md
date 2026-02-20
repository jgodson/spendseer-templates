# SpendSeer Community Templates

Public catalog of community-maintained SpendSeer import templates.

This repo is focused on template authoring and contribution workflow.  
Contributors edit YAML/CSV source files, and CI validates + builds JSON and static pages for discovery and install.

## Repository layout

- `templates/<slug>/<version>/template.yml`
- `templates/<slug>/<version>/meta.yml`
- `templates/<slug>/<version>/README.md`
- `templates/<slug>/<version>/example.csv`
- `schemas/` (validation schemas)
- `scripts/validate.rb`
- `scripts/build.rb`
- `dist/` (generated output)

## Naming conventions

- `slug`: lowercase kebab-case and globally unique  
  Regex: `^[a-z0-9]+(?:-[a-z0-9]+)*$`
- `version` directory: `v`-prefixed semantic-ish version  
  Examples: `v1`, `v2`, `v2.1`, `v2.1.3`  
  Regex: `^v\d+(?:\.\d+){0,2}$`
- Canonical identity is the directory path: `templates/<slug>/<version>/`

## Version behavior

- Multiple versions per slug are supported.
- Detail pages include a version selector.
- Latest version is selected by semantic sort.

## Local development

Validate template sources:

```bash
ruby scripts/validate.rb
```

Build generated artifacts:

```bash
ruby scripts/build.rb
```

Optional local preview:

```bash
cd dist/site
python3 -m http.server 8080
# open http://127.0.0.1:8080
```

## Build output

- `dist/catalog.json`
- `dist/templates/<slug>/<version>/template.json`
- `dist/site/index.html`
- `dist/site/templates/<slug>/index.html`

`catalog.json` version records include:

- `source_url`
- `template_sha256` (SHA-256 of generated `template.json`)
- `app_review_url` (deep-link to SpendSeer app review/install page)

## Optional environment variables

- `RAW_TEMPLATE_BASE_URL`
  - Base URL used to generate `source_url` values in `catalog.json`
  - Example: `https://raw.githubusercontent.com/<owner>/<repo>/main/dist`
- `SITE_BASE_URL`
  - Base URL for generated detail/template links
  - Example: `https://example.com`
  - If `RAW_TEMPLATE_BASE_URL` is unset, `source_url` uses `SITE_BASE_URL`
- `APP_INSTALL_BASE_URL`
  - Base URL for install/review links in generated pages
  - Default: `https://app.spendseer.com`

## Contributing

See `CONTRIBUTING.md`.
