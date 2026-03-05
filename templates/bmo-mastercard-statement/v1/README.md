# BMO Mastercard Statement CSV (v1)

## Best for

BMO Mastercard statement exports with `Posting Date`, `Description`, and `Transaction Amount`.

## CSV location

Export your statement activity from BMO as CSV.

## Notes

- BMO exports include a preamble line (`Following data is valid as of...`) and a blank line before the CSV headers. `skip_rows: 2` in this template handles that automatically.
- Category is intentionally not mapped; SpendSeer category rules should classify using description.
