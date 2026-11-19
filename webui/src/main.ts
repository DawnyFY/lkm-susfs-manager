import { createApp } from "vue";
import App from "./App.vue";
import { initI18n } from "./i18n";
import { applyTheme, currentTheme } from "./theme";
import "./styles/base.css";

applyTheme(currentTheme());
initI18n();
createApp(App).mount("#app");
