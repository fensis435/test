import React from 'react';
import {
  GridRenderEditCellParams,
  useGridApiContext,
} from '@mui/x-data-grid';
import {
  Box,
  Chip,
  IconButton,
  Paper,
  MenuList,
  MenuItem,
  Popper,
  ClickAwayListener,
} from '@mui/material';
import MoreVertIcon from '@mui/icons-material/MoreVert';
import ArrowRightIcon from '@mui/icons-material/ArrowRight';

export interface MenuNode {
  id: string;
  label: string;
  children?: MenuNode[];
}

export default function TagEditCell({ id, field, value, menuTree, loading, error, }: GridRenderEditCellParams & {
  menuTree: MenuNode[];
  loading: boolean;
  error: string | null;
}) {
  const apiRef = useGridApiContext();
  const [levels, setLevels] = React.useState<
    { anchorEl: HTMLElement; items: MenuNode[] }[]
  >([]);

  const closeAll = () => setLevels([]);

  // only call startCellEditMode if the cell is in view mode
  const openRoot = (e: React.MouseEvent<HTMLElement>) => {
    e.stopPropagation();
    const cellMode = apiRef.current.getCellMode(id, field);
    if (cellMode === 'view') {
      apiRef.current.startCellEditMode({ id, field });
    }
    setLevels([{ anchorEl: e.currentTarget, items: menuTree }]);
  };

  const handleHover = (
    node: MenuNode,
    level: number,
    anchorEl: HTMLElement
  ) => {
    if (node.children) {
      setLevels((prev) => {
        const next = prev.slice(0, level + 1);
        next[level + 1] = { anchorEl, items: node.children! };
        return next;
      });
    } else {
      setLevels((prev) => prev.slice(0, level + 1));
    }
  };

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
    <ClickAwayListener onClickAway={closeAll}>
      <Box display="flex" alignItems="center">
        {Array.isArray(value) &&
          value.map((tag) => (
            <Chip key={tag} label={tag} size="small" sx={{ mr: 0.5 }} />
          ))}
        <IconButton
          size="small"
          onClick={openRoot}
          disabled={loading || Boolean(error)}
        >
          <MoreVertIcon fontSize="small" />
        </IconButton>
        {levels.map(({ anchorEl, items }, level) => (
          <Popper
            key={level}
            open
            anchorEl={anchorEl}
            placement={level === 0 ? 'bottom-start' : 'right-start'}
            modifiers={[
              { name: 'offset', options: { offset: [0, 4] } },
              { name: 'preventOverflow', options: { padding: 8 } },
              { name: 'flip', options: { padding: 8 } },
            ]}
            style={{ zIndex: 1300 + level }}
          >
            <Paper elevation={3}>
              <MenuList autoFocusItem={false}>
                {items.map((node) => (
                  <MenuItem
                    key={node.id}
                    onMouseEnter={(e) =>
                      handleHover(node, level, e.currentTarget)
                    }
                    onClick={(e) => {
                      if (!node.children) {
                        handleSelect(node.id, e);
                      }
                    }}
                    sx={{
                      display: 'flex',
                      justifyContent: 'space-between',
                      minWidth: 160,
                    }}
                  >
                    {node.label}
                    {node.children && <ArrowRightIcon fontSize="small" />}
                  </MenuItem>
                ))}
              </MenuList>
            </Paper>
          </Popper>
        ))}
      </Box>
    </ClickAwayListener>
  );
}
