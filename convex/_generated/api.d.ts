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
import type * as composio from "../composio.js";
import type * as connections from "../connections.js";
import type * as crons from "../crons.js";
import type * as emailClient from "../emailClient.js";
import type * as fieldCaps from "../fieldCaps.js";
import type * as handleKeys from "../handleKeys.js";
import type * as handleNames from "../handleNames.js";
import type * as http from "../http.js";
import type * as imageBlobs from "../imageBlobs.js";
import type * as loveAlarm from "../loveAlarm.js";
import type * as memories from "../memories.js";
import type * as nameSearch from "../nameSearch.js";
import type * as openaiClient from "../openaiClient.js";
import type * as people from "../people.js";
import type * as peopleFields from "../peopleFields.js";
import type * as profileFields from "../profileFields.js";
import type * as profiles from "../profiles.js";
import type * as rateLimit from "../rateLimit.js";
import type * as sharedNotes from "../sharedNotes.js";
import type * as stripe from "../stripe.js";
import type * as stripeFields from "../stripeFields.js";
import type * as waitlist from "../waitlist.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  authz: typeof authz;
  captures: typeof captures;
  composio: typeof composio;
  connections: typeof connections;
  crons: typeof crons;
  emailClient: typeof emailClient;
  fieldCaps: typeof fieldCaps;
  handleKeys: typeof handleKeys;
  handleNames: typeof handleNames;
  http: typeof http;
  imageBlobs: typeof imageBlobs;
  loveAlarm: typeof loveAlarm;
  memories: typeof memories;
  nameSearch: typeof nameSearch;
  openaiClient: typeof openaiClient;
  people: typeof people;
  peopleFields: typeof peopleFields;
  profileFields: typeof profileFields;
  profiles: typeof profiles;
  rateLimit: typeof rateLimit;
  sharedNotes: typeof sharedNotes;
  stripe: typeof stripe;
  stripeFields: typeof stripeFields;
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

export declare const components: {
  rateLimiter: import("@convex-dev/rate-limiter/_generated/component.js").ComponentApi<"rateLimiter">;
};
