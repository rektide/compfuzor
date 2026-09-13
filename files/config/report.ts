/** Shared row representation and rendering for CONFIG observations. */

export type StatusFormat = "human" | "jsonl" | "array"
export type StatusSeverity = "ok" | "drift" | "error"

export type StatusRow = {
  kind: "input" | "output" | "assembly"
  status: string
  severity: StatusSeverity
  config: string
  name: string
  state?: string
  representation?: string
  source?: string
  destination?: string
  note?: string
}

export function statusCode(rows: StatusRow[]): number {
  if (rows.some((row) => row.severity === "error")) return 2
  return rows.some((row) => row.severity === "drift") ? 1 : 0
}

export function printStatusRows(rows: StatusRow[], format: StatusFormat): void {
  if (format === "array") {
    console.log(JSON.stringify(rows, null, 2))
    return
  }
  if (format === "jsonl") {
    for (const row of rows) console.log(JSON.stringify(row))
    return
  }
  if (rows.length === 0) return
  console.log("kind\tstatus\tconfig\tname\tstate\trepresentation\tsource\tdestination\tnote")
  for (const row of rows) {
    console.log([
      row.kind, row.status, row.config, row.name, row.state ?? "-", row.representation ?? "-",
      row.source ?? "-", row.destination ?? "-", row.note ?? "-",
    ].join("\t"))
  }
}
