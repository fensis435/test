import { FC } from "react";

import { NAVIGATION_ITEMS } from "./NavigationItems";
import { NavigationList } from "../NavigationList";
import type { NavigationDrawerChildProps } from "../NavigationDrawer";

export const AppNavigationList: FC<NavigationDrawerChildProps> = ({
  isHover,
  isOpen,
  variant
}) => {
  return (
    <NavigationList
      items={NAVIGATION_ITEMS}
      forceCollapse={variant === "permanent" && !isHover && !isOpen}
    />
  );
};
