import React, { useState } from "react";
import { IconButton, Menu, MenuItem, FormGroup, FormControlLabel, Checkbox } from "@mui/material";
import SettingsIcon from "@mui/icons-material/Settings";

const GraphSettingMenu = ({ onSettingsChange }) => {
  const [anchorEl, setAnchorEl] = useState(null);
  const [categories, setCategories] = useState({
    category1: { optionA: false, optionB: false },
    category2: { optionC: false, optionD: false },
  });

  const handleOpen = (event) => {
    setAnchorEl(event.currentTarget);
  };

  const handleClose = () => {
    setAnchorEl(null);
  };

  const handleCheckboxChange = (category, option) => {
    const updatedCategories = {
      ...categories,
      [category]: {
        ...categories[category],
        [option]: !categories[category][option],
      },
    };
    setCategories(updatedCategories);
    onSettingsChange(updatedCategories);
  };


  return (
    <div>
      {/* Settingsアイコンを使用したアイコンボタン */}
      <IconButton onClick={handleOpen}>
        <SettingsIcon style={{ color: "white" }} />
      </IconButton>
      <Menu
        anchorEl={anchorEl}
        open={Boolean(anchorEl)}
        onClose={handleClose}
      >
        <MenuItem>
          <FormGroup>
            <strong>Category 1</strong>
            <FormControlLabel
              control={
                <Checkbox
                  checked={categories.category1.optionA}
                  onChange={() => handleCheckboxChange("category1", "optionA")}
                />
              }
              label="Option A"
            />
            <FormControlLabel
              control={
                <Checkbox
                  checked={categories.category1.optionB}
                  onChange={() => handleCheckboxChange("category1", "optionB")}
                />
              }
              label="Option B"
            />
          </FormGroup>
        </MenuItem>
        <MenuItem>
          <FormGroup>
            <strong>Category 2</strong>
            <FormControlLabel
              control={
                <Checkbox
                  checked={categories.category2.optionC}
                  onChange={() => handleCheckboxChange("category2", "optionC")}
                />
              }
              label="Option C"
            />
            <FormControlLabel
              control={
                <Checkbox
                  checked={categories.category2.optionD}
                  onChange={() => handleCheckboxChange("category2", "optionD")}
                />
              }
              label="Option D"
            />
          </FormGroup>
        </MenuItem>
      </Menu>
    </div>
  );
};

export default GraphSettingMenu;
