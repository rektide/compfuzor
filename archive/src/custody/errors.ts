/** Custody errors are data for the CLI boundary, never a partial success result. */
export type CustodyFailure =
  | "invalid-input"
  | "unsupported-repository"
  | "inspection-failed"
  | "source-drift"
  | "destination-drift"
  | "occupied-namespace"
  | "different-receipt"
  | "bundle-invalid"
  | "ref-race"
  | "verification-failed";

export class CustodyError extends Error {
  public readonly code: CustodyFailure;
  public readonly subject: string | null;
  public constructor(code: CustodyFailure, message: string, subject: string | null = null) {
    super(message);
    this.name = "CustodyError";
    this.code = code;
    this.subject = subject;
  }
}

export function invalid(message: string): never {
  throw new CustodyError("invalid-input", message);
}
