import { Box, Drawer as MuiDrawer } from '@mui/material';
import type { DrawerProps } from '@mui/material/Drawer';
import type { CSSObject } from '@mui/styled-engine';
import { styled } from '@mui/material/styles';
import { FC, ReactNode, useMemo, useState } from 'react';

const MiniVariantDrawer = styled(MuiDrawer, {
  shouldForwardProp: (prop) =>
    prop !== 'open' &&
    prop !== 'isHover' &&
    prop !== 'width' &&
    prop !== 'keepMounted'
})<DrawerProps & { width: number; isHover?: boolean }>(({
  theme,
  open,
  width,
  isHover
}) => {
  const drawerWidth = open
    ? width
    : // border分加える
      `calc(${theme.spacing(7)} + 1px)`;
  const drawerAndPaperStyles: CSSObject = {
    width: drawerWidth,
    transition: theme.transitions.create('width', {
      easing: theme.transitions.easing.sharp,
      duration: theme.transitions.duration.leavingScreen
    }),
    overflowX: 'hidden'
  };
  return {
    flexShrink: 0,
    whiteSpace: 'nowrap',
    ...drawerAndPaperStyles,
    '& .MuiDrawer-paper': {
      ...drawerAndPaperStyles,
      width: isHover ? width : drawerWidth
    }
  };
});

export type NavigationDrawerChildProps = {
  /** ドロワー部分hover時 */
  isHover: boolean;
  /** ドロワーオープン時 */
  isOpen: boolean;
  /** ドロワーのバリアント状態 */
  variant: NavigationDrawerProps['variant'];
};

export type NavigationDrawerProps = {
  /** 開閉フラグ */
  isOpen: boolean;
  /** ドロワーの幅 */
  width?: number;
  /** バリアント */
  variant: 'temporary' | 'permanent';
  /** トップの高さを調整するためだけに表示するコンポーネント（Toolbar） */
  PaddingComponent: FC<any>;
  /** 閉じる時 */
  onClose: DrawerProps['onClose'];
  /** ドロワーコンテンツ */
  children: FC<NavigationDrawerChildProps> | ReactNode;
};

export const NavigationDrawer: FC<NavigationDrawerProps> = ({
  isOpen,
  width = 250,
  variant,
  PaddingComponent,
  onClose,
  children: Child
}) => {
  const [isHover, setIsHover] = useState(false);
  const Drawer = variant === 'temporary' ? MuiDrawer : MiniVariantDrawer;

  const childContent = useMemo(() => {
    return typeof Child === 'function' ? (
      <Child isHover={isHover} isOpen={isOpen} variant={variant} />
    ) : (
      Child
    );
  }, [Child, isHover, isOpen, variant]);

  const additionalProps =
    variant === 'permanent'
      ? {
          isHover
        }
      : {};
  return (
    <Drawer
      open={isOpen}
      width={width}
      anchor='left'
      variant={variant}
      keepMounted
      {...additionalProps}
      onMouseEnter={() => {
        setIsHover(true);
      }}
      onMouseLeave={() => {
        setIsHover(false);
      }}
      onClose={onClose}
    >
      {variant === 'permanent' && <PaddingComponent />}
      <Box sx={{ width, overflowX: 'hidden', overflowY: 'auto' }}>
        {childContent}
      </Box>
    </Drawer>
  );
};
