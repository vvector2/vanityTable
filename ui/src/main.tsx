import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "@picocss/pico/css/pico.min.css";
import App from "./App";
import { ensureSignedIn } from "./auth";
import { ListingsProvider } from "./state/ListingsContext";
import { ScanProvider } from "./state/ScanContext";
import "./index.css";

const root = createRoot(document.getElementById("root")!);

ensureSignedIn()
  .then((user) => {
    // No user: the browser is on its way to the Cognito sign-in page.
    if (!user) return;
    root.render(
      <StrictMode>
        <ListingsProvider>
          <ScanProvider>
            <App />
          </ScanProvider>
        </ListingsProvider>
      </StrictMode>,
    );
  })
  .catch(() => {
    root.render(<p className="empty-state">Logowanie nie powiodło się. Odśwież stronę.</p>);
  });
