import React from 'react';
import {
  GridRenderEditCellParams,
  useGridApiContext,
} from '@mui/x-data-grid';
import {
  Box,
  Chip,
  IconButton,
  Menu,
  MenuItem,
  TextField,
  MenuListProps,
} from '@mui/material';
import MoreVertIcon from '@mui/icons-material/MoreVert';
import ArrowRightIcon from '@mui/icons-material/ArrowRight';

export interface MenuNode {
  id: string;
  label: string;
  children?: MenuNode[];
}

export interface TagEditCellProps
  extends GridRenderEditCellParams {
  menuTree: MenuNode[];
  loading: boolean;
  error: string | null;
}

const FILTER_THRESHOLD = 100;

const TagEditCell: React.FC<TagEditCellProps> = ({
  id,
  field,
  value,
  menuTree,
  loading,
  error,
}) => {
  const apiRef = useGridApiContext();
  const [filter, setFilter] = React.useState('');
  const [anchorEl, setAnchorEl] =
    React.useState<HTMLElement | null>(null);
  const [subMenu, setSubMenu] = React.useState<{
    anchorEl: HTMLElement | null;
    items: MenuNode[];
  }>({ anchorEl: null, items: [] });

  const openMain = (e: React.MouseEvent<HTMLElement>) =>
    setAnchorEl(e.currentTarget);
  const closeAll = () => {
    setAnchorEl(null);
    setSubMenu({ anchorEl: null, items: [] });
  };
  const openSub = (
    e: React.MouseEvent<HTMLElement>,
    items: MenuNode[]
  ) =>
    setSubMenu({ anchorEl: e.currentTarget, items });
  const closeSub = () =>
    setSubMenu({ anchorEl: null, items: [] });

  const handleSelect = (
    tagId: string,
    e: React.MouseEvent<HTMLElement>
  ) => {
    e.stopPropagation();
    const current = Array.isArray(value) ? [...value] : [];
    if (!current.includes(tagId)) {
      apiRef.current.setEditCellValue(
        { id, field, value: [...current, tagId] },
        e
      );
    }
    closeAll();
  };

  // フィルター適用
  const filterTree = React.useCallback(
    (nodes: MenuNode[]): MenuNode[] => {
      if (!filter) return nodes;
      const lower = filter.toLowerCase();
      return nodes
        .map((n) => {
          const parentMatch = n.label
            .toLowerCase()
            .includes(lower);
          const childMatch = n.children
            ? n.children.filter((c) =>
                c.label.toLowerCase().includes(lower)
              )
            : [];
          if (parentMatch || childMatch.length > 0) {
            return { ...n, children: childMatch } as MenuNode;
          }
          return null;
        })
        .filter((n): n is MenuNode => n !== null);
    },
    [filter]
  );

  const mainItems = filterTree(menuTree);
  const subItems = filter
    ? subMenu.items.filter((c) =>
        c.label.toLowerCase().includes(filter.toLowerCase())
      )
    : subMenu.items;

  return (
    <Box display="flex" alignItems="center">
      {/* 既存タグChip */}
      {Array.isArray(value) &&
        value.map((tag) => (
          <Chip
            key={tag}
            label={tag}
            size="small"
            sx={{ mr: 0.5 }}
          />
        ))}

      {/* メニュー開閉ボタン */}
      <IconButton
        size="small"
        onClick={openMain}
        disabled={loading || Boolean(error)}
      >
        <MoreVertIcon fontSize="small" />
      </IconButton>

      {/* 親メニュー */}
      <Menu
        anchorEl={anchorEl}
        open={Boolean(anchorEl)}
        onClose={closeAll}
        MenuListProps={{
          autoFocusItem: true,
        } as MenuListProps}
      >
        {/* 検索フィールド */}
        {mainItems.length > FILTER_THRESHOLD && (
          <Box px={1} py={0.5}>
            <TextField
              placeholder="検索…"
              size="small"
              fullWidth
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
            />
          </Box>
        )}
        {mainItems.map((node) => (
          <MenuItem
            key={node.id}
            onMouseEnter={(e) =>
              node.children && openSub(e, node.children)
            }
            onClick={(e) =>
              !node.children && handleSelect(node.id, e)
            }
          >
            {node.label}
            {node.children && (
              <ArrowRightIcon fontSize="small" />
            )}
          </MenuItem>
        ))}
      </Menu>

      {/* サブメニュー */}
      <Menu
        anchorEl={subMenu.anchorEl}
        open={Boolean(subMenu.anchorEl)}
        onClose={closeSub}
        anchorOrigin={{
          vertical: 'top',
          horizontal: 'right',
        }}
        transformOrigin={{
          vertical: 'top',
          horizontal: 'left',
        }}
        MenuListProps={{
          onMouseLeave: closeSub,
          autoFocusItem: true,
        } as MenuListProps}
      >
        {subItems.length > FILTER_THRESHOLD && (
          <Box px={1} py={0.5}>
            <TextField
              placeholder="サブ検索…"
              size="small"
              fullWidth
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
            />
          </Box>
        )}
        {subItems.map((child) => (
          <MenuItem
            key={child.id}
            onClick={(e) => handleSelect(child.id, e)}
          >
            {child.label}
          </MenuItem>
        ))}
      </Menu>
    </Box>
  );
};

export default TagEditCell;
