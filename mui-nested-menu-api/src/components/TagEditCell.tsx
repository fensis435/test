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
} from '@mui/material';
import MoreVertIcon from '@mui/icons-material/MoreVert';
import ArrowRightIcon from '@mui/icons-material/ArrowRight';

export interface MenuNode {
  id: string;
  label: string;
  children?: MenuNode[];
}

interface TagEditCellProps extends GridRenderEditCellParams {
  menuTree: MenuNode[];
  loading: boolean;
  error: string | null;
}

export default function TagEditCell(props: TagEditCellProps) {
  const { id, field, value, menuTree, loading, error } = props;
  const apiRef = useGridApiContext();

  // 各階層のメニュー状態を配列で管理
  // levels[i] = { anchorEl, items } は i階層目のメニューを示す
  const [levels, setLevels] = React.useState<
    { anchorEl: HTMLElement | null; items: MenuNode[] }[]
  >([]);

  // i階層目を開く／書き換える
  const openLevel = (
    level: number,
    anchorEl: HTMLElement,
    items: MenuNode[]
  ) => {
    setLevels((prev) => {
      const next = prev.slice(0, level);
      next[level] = { anchorEl, items };
      return next;
    });
  };

  // 全閉じ
  const closeAll = () => setLevels([]);

  // タグ選択
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

  return (
    <Box display="flex" alignItems="center">
      {/* 既存タグChip */}
      {Array.isArray(value) &&
        value.map((tag: string) => (
          <Chip key={tag} label={tag} size="small" sx={{ mr: 0.5 }} />
        ))}

      {/* メニュー開閉ボタン */}
      <IconButton
        size="small"
        onClick={(e) =>
          openLevel(0, e.currentTarget, menuTree)
        }
        disabled={loading || Boolean(error)}
      >
        <MoreVertIcon fontSize="small" />
      </IconButton>

      {/* 各階層の Menu を動的レンダー */}
      {levels.map(({ anchorEl, items }, lvl) => (
        <Menu
          key={lvl}
          anchorEl={anchorEl}
          open={Boolean(anchorEl)}
          onClose={closeAll}
          // 第1階層だけデフォルト表示、それ以外は右に並べる
          anchorOrigin={
            lvl === 0
              ? { vertical: 'bottom', horizontal: 'left' }
              : { vertical: 'top', horizontal: 'right' }
          }
          transformOrigin={
            lvl === 0
              ? { vertical: 'top', horizontal: 'left' }
              : { vertical: 'top', horizontal: 'left' }
          }
          // サブ階層ではホバー外で一つ上に戻す
          MenuListProps={
            lvl > 0
              ? {
                  onMouseLeave: () =>
                    setLevels((prev) => prev.slice(0, lvl)),
                }
              : undefined
          }
        >
          {items.map((node) => (
            <MenuItem
              key={node.id}
              onMouseEnter={(e) =>
                node.children &&
                openLevel(lvl + 1, e.currentTarget, node.children)
              }
              onClick={(e) =>
                !node.children && handleSelect(node.id, e)
              }
            >
              {node.label}
              {node.children && (
                <ArrowRightIcon
                  fontSize="small"
                  sx={{ ml: 1 }}
                />
              )}
            </MenuItem>
          ))}
        </Menu>
      ))}
    </Box>
  );
}
