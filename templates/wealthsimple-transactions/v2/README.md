# Wealthsimple Credit Card Statement CSV (v2)

## Best for

Official Wealthsimple credit card statement exports with these columns:

- `transaction_date`
- `post_date`
- `type`
- `details`
- `amount`
- `currency`

## CSV location

Export statement transactions from Wealthsimple as CSV.

## Notes

- `transaction_date` is used as the import date.
- No category column is mapped; category rules should classify using `details`.
- `Payment` rows may appear and can be removed before import if you do not want card payments included.
