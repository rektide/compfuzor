/**
 * Compatibility re-export; the substantive shell boundary lives in
 * repository/jj.ts. Design briefs and the CLI still link these flat paths.
 */
export {
  JjError,
  jj,
  lines,
  exists,
  isDirectory,
  REF_TEMPLATE,
  COMMIT_TEMPLATE,
  HEAD_TEMPLATE,
  refKey,
  refs,
  revision,
  ancestor,
} from "./repository/jj.ts";
export type { BookmarkRef, Revision } from "./repository/jj.ts";
