# RBC Chequing Account CSV (v1)

## Best for

RBC chequing account exports with these columns:

- `Account Type`
- `Account Number`
- `Transaction Date`
- `Cheque Number`
- `Description 1`
- `Description 2`
- `CAD$`
- `USD$`

## How to export

1. Log into RBC Online Banking
2. Select the account you want to export
3. Click **Download**
4. Choose **CSV**

## Notes

- The template imports `Transaction Date`, `Description 1`, and `CAD$`.
- Amounts are already signed correctly: negative values are money out, positive values are money in.
- `Account Number`, `Cheque Number`, `Description 2`, and `USD$` are ignored by this version.
- If your export uses `USD$` or you want to use another source column, you can still import this template as a starting point and then adjust the mapping in SpendSeer before completing the import.
