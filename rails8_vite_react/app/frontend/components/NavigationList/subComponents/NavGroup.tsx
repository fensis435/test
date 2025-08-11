import { Collapse, List } from '@mui/material';
import { FC } from 'react';

import type { AccordionManager } from '../hooks/useAccordionManager';
import type { NavigationGroupItem } from '../NavigationItemType';
import { NavGroupHeader } from './NavGroupHeader';
import { NavItem } from './NavItem';

export type NavGroupProps = {
  /** グループ項目 */
  item: NavigationGroupItem;
  /** ナビゲーションの番地 */
  navIndexes: number[];
  /** アコーディオン情報を管理するインスタンス */
  accordionManager: AccordionManager;
};

export const NavGroup: FC<NavGroupProps> = ({
  item,
  navIndexes,
  accordionManager
}) => {
  const isOpen = accordionManager.isOpen(navIndexes);

  return (
    <>
      <NavGroupHeader
        isOpen={isOpen}
        item={item}
        navIndexes={navIndexes}
        onToggle={() => {
          accordionManager.toggle(navIndexes);
        }}
      />
      <Collapse in={isOpen} timeout='auto'>
        <List disablePadding>
          {item.subs.map((subItem, index) =>
            'subs' in subItem ? (
              <NavGroup
                key={index}
                item={subItem}
                navIndexes={[...navIndexes, index]}
                accordionManager={accordionManager}
              />
            ) : (
              <NavItem
                key={index}
                item={subItem}
                navIndexes={[...navIndexes, index]}
              />
            )
          )}
        </List>
      </Collapse>
    </>
  );
};
