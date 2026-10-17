import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "@picocss/pico/css/pico.min.css";
import App from "./App";
import { ListingsProvider } from "./state/ListingsContext";
import "./index.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ListingsProvider>
      <App />
    </ListingsProvider>
  </StrictMode>,
);
