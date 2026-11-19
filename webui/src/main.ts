import { createApp } from "vue";
import App from "./App.vue";
import { initI18n } from "./i18n";
import { applyTheme, currentTheme, themeFromQuery } from "./theme";
import "./styles/base.css";

// ?theme=warm 只影响本次渲染，不落盘
applyTheme(themeFromQuery() ?? currentTheme());
initI18n();
createApp(App).mount("#app");
