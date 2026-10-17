import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "@picocss/pico/css/pico.min.css";
import App from "./App.jsx";
import { ListingsProvider } from "./state/ListingsContext.jsx";
import "./index.css";

createRoot(document.getElementById("root")).render(
  <StrictMode>
    <ListingsProvider>
      <App />
    </ListingsProvider>
  </StrictMode>,
);
