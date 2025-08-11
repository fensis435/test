import {
  Link,
  ListItemButton,
  ListItemIcon,
  ListItemText
} from "@mui/material";
import { FC } from "react";
import { Link as RouterLink, useLocation } from "react-router-dom";

import type { NavigationSingleItem } from "../NavigationItemType";

export type NavItemProps = {
  /** 単一項目 */
  item: NavigationSingleItem;
  /** ナビゲーションの番地 */
  navIndexes: number[];
};

export const NavItem: FC<NavItemProps> = ({ item, navIndexes }) => {
  const Icon = item.icon;
  const depth = navIndexes.length - 1;

  const { pathname } = useLocation();

  return (
    <Link
      component={RouterLink}
      to={item.href}
      underline="none"
      color="inherit"
    >
      <ListItemButton
        sx={{
          pl: Math.max(2 * depth, 2),
          minHeight: depth === 0 ? "56px" : "48px"
        }}
        selected={item.href === pathname}
      >
        {Icon && (
          <ListItemIcon>
            <Icon />
          </ListItemIcon>
        )}
        <ListItemText primary={item.title} inset={Icon == null} />
      </ListItemButton>
    </Link>
  );
};
