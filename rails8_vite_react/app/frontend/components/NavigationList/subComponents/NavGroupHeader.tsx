import { ListItemButton, ListItemIcon, ListItemText } from "@mui/material";
import {
  ArrowDropDown as ArrowDropDownIcon,
  ExpandMore as ExpandMoreIcon
} from "@mui/icons-material";
import { FC } from "react";

import type { NavigationGroupItem } from "../NavigationItemType";

export type NavGroupHeaderProps = {
  /** 開閉フラグ */
  isOpen: boolean;
  /** グループ項目 */
  item: NavigationGroupItem;
  /** ナビゲーションの番地 */
  navIndexes: number[];
  /** 開閉フラグをトグルする */
  onToggle: () => void;
};

export const NavGroupHeader: FC<NavGroupHeaderProps> = ({
  isOpen,
  item,
  navIndexes,
  onToggle
}) => {
  const Icon = item.icon;
  const depth = navIndexes.length - 1;

  return (
    <ListItemButton
      color="primary"
      sx={{ minHeight: "56px" }}
      onClick={() => {
        onToggle();
      }}
    >
      {Icon && (
        <ListItemIcon>
          <Icon />
        </ListItemIcon>
      )}
      {/* depthに応じた判断は別に切り出していた方が良いかも */}
      {depth === 1 && (
        <ListItemIcon
          sx={{
            justifyContent: "center"
          }}
        >
          <ArrowDropDownIcon
            sx={{
              transform: `rotate(${isOpen ? 180 : 0}deg)`,
              transition: "transform 0.3s"
            }}
          />
        </ListItemIcon>
      )}
      <ListItemText primary={item.title} inset={depth < 1 && Icon == null} />
      {depth === 0 && (
        <ExpandMoreIcon
          sx={{
            // ListItemIconでデフォルトで設定されている色をセットする
            color: "rgba(0, 0, 0, 0.54)",
            transform: `rotate(${isOpen ? 180 : 0}deg)`,
            transition: "transform 0.3s"
          }}
        />
      )}
    </ListItemButton>
  );
};
