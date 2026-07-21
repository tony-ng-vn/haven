/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as authz from "../authz.js";
import type * as captures from "../captures.js";
import type * as crons from "../crons.js";
import type * as loveAlarm from "../loveAlarm.js";
import type * as nameSearch from "../nameSearch.js";
import type * as openaiClient from "../openaiClient.js";
import type * as people from "../people.js";
import type * as profiles from "../profiles.js";
import type * as rateLimit from "../rateLimit.js";
import type * as sharedNotes from "../sharedNotes.js";
import type * as waitlist from "../waitlist.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  authz: typeof authz;
  captures: typeof captures;
  crons: typeof crons;
  loveAlarm: typeof loveAlarm;
  nameSearch: typeof nameSearch;
  openaiClient: typeof openaiClient;
  people: typeof people;
  profiles: typeof profiles;
  rateLimit: typeof rateLimit;
  sharedNotes: typeof sharedNotes;
  waitlist: typeof waitlist;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
