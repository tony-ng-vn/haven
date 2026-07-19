// The published feedback-sdk-widget package ships its JS bundles without a
// bundled .d.ts, so the dynamic import("feedback-sdk-widget") has nothing to
// resolve types from. The module is imported only for its custom-element
// registration side effect, so an empty ambient declaration is enough. This
// file has no imports/exports on purpose: that keeps it a global script so the
// declaration is ambient rather than a module augmentation.
declare module "feedback-sdk-widget";
