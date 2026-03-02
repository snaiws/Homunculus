import type { OpenClawPluginApi } from "openclaw/plugin-sdk";
import { emptyPluginConfigSchema } from "openclaw/plugin-sdk";

const plugin = {
  id: "homunculus-core",
  name: "Homunculus Core",
  description: "Core plugin for Homunculus — the dwarf in the flask",
  configSchema: emptyPluginConfigSchema(),

  register(api: OpenClawPluginApi) {
    const logger = api.logger;
    logger.info("Homunculus core plugin loading...");

    // --- Lifecycle: Gateway Start ---
    api.on("gateway_start", () => {
      logger.info("Homunculus has awakened. 🧪");
    });

    // --- Lifecycle: Gateway Stop ---
    api.on("gateway_stop", () => {
      logger.info("Homunculus is going to sleep...");
    });

    // --- Lifecycle: Session Start ---
    api.on("session_start", () => {
      logger.info("New conversation session started.");
    });

    logger.info("Homunculus core plugin loaded successfully.");
  },
};

export default plugin;
