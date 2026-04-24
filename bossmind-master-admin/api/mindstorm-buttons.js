const express = require("express");
const router = express.Router();

const { MINDSTORM_BUTTONS } = require("../../bossmind-shared/automation/mindstorm-button-registry");

router.get("/mindstorm-buttons", (req, res) => {
  res.json({
    success: true,
    buttons: MINDSTORM_BUTTONS,
  });
});

module.exports = router;