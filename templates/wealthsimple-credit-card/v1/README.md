# Wealthsimple Transactions CSV (v1)

> **This template covers the manual CSV export method that existed before Wealthsimple supported native CSV exports. It is recommended to use [v2](../v2/) instead.**
>
> For full context and instructions for this version, see the [appendix on jasongodson.com](https://jasongodson.com/blog/wealthsimple-csv-export/#appendix).

## Best for

Wealthsimple exports with `Date`, `Description`, and `Amount` columns.

## How to export

1. Go to your Credit Card page in Wealthsimple
2. Click **View All** to see the full transaction list
3. Click **Load More** until all transactions you want are visible
4. Open the browser console (F12 or right-click → Inspect → Console) and run the following script:

```js
(function () {
  const rows = [];
  const buttons = document.querySelectorAll("button");
  function findNearestDateHeader(startEl) {
    let el = startEl;
    let date = null;
    while (el && !date) {
      el = el.previousElementSibling || el.parentElement;
      if (!el) break;
      if (el.tagName === "H2" && /(\d{4}\b)|Today|Yesterday/i.test(el.textContent || "")) {
        date = (el.textContent || "").trim();
      }
    }
    return date;
  }
  function normalizeAmountText(text) {
    return text ? text.replace(/\u2212/g, "-").replace(/\s+/g, " ").trim() : text;
  }
  buttons.forEach((button) => {
    const date = findNearestDateHeader(button);
    if (!date) return;
    const ps = button.querySelectorAll("p");
    const description = (ps[0]?.textContent || "").trim();
    if (!description) return;
    let amount = null;
    for (const p of ps) {
      let text = (p.textContent || "").trim();
      text = normalizeAmountText(text);
      if (/[−-]\s*\$\s*\d/.test(text) || /\$\s*\d/.test(text)) {
        amount = text;
        break;
      }
    }
    if (!amount) return;
    rows.push([date, description, amount]);
  });
  const uniqueRows = Array.from(new Set(rows.map((r) => r.join("|")))).map((s) => s.split("|"));
  function csvEscape(value) {
    const str = String(value ?? "");
    if (/[,"\n]/.test(str)) {
      return `"${str.replace(/"/g, '""')}"`;
    }
    return str;
  }
  const csvHeader = ["Date", "Description", "Amount"];
  const csvRows = [csvHeader, ...uniqueRows];
  const csvText = csvRows.map((row) => row.map(csvEscape).join(",")).join("\n");
  const blob = new Blob([csvText], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "transactions.csv";
  link.style.display = "none";
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
})();
```

## Notes

- Amounts are sign-adjusted so spending and inflows import correctly.
- No category column is mapped; use category rules to categorize.
