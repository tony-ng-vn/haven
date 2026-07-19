import type { DetailedHTMLProps, HTMLAttributes } from "react";

declare module "react" {
  namespace JSX {
    interface IntrinsicElements {
      "feedback-widget": DetailedHTMLProps<
        HTMLAttributes<HTMLElement> & {
          endpoint?: string;
          token?: string;
          categories?: string;
          "page-context"?: string;
          label?: string;
          submitter?: string;
        },
        HTMLElement
      >;
    }
  }
}
