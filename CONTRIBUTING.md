# Contributing Templates

## 1. Pick a unique slug

Create a folder under `templates/<slug>/`.

Rules:

- Use lowercase kebab-case.
- Do not reuse an existing slug.

## 2. Add a version directory

Create `templates/<slug>/<version>/` where version matches:

- `v1`
- `v2`
- `v2.1`
- `v2.1.3`

## 3. Add required files

Each version folder must contain:

- `template.yml`
- `meta.yml`
- `README.md`
- `example.csv`

## 4. Required metadata

- `meta.yml` `slug` and `version` must match folder names.
- `template.yml` metadata must include:
  - `community_slug`
  - `community_version`
- `target_type` must be `transactions` or `budgets`.
- `source_type` must be `csv`.

## 5. Run checks locally

```bash
ruby scripts/validate.rb
ruby scripts/build.rb
```

## 6. Open a PR

CI validates templates and builds site artifacts.
