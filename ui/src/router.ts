import { useEffect, useState } from "react";

// Hash routes, so S3 and CloudFront serve index.html for every page without rewrite rules.
export type Route = { page: "home" } | { page: "search"; searchId: string };

export function searchHref(searchId: string): string {
  return `#/searches/${encodeURIComponent(searchId)}`;
}

function parse(hash: string): Route {
  const id = /^#\/searches\/([^/]+)$/.exec(hash)?.[1];
  return id ? { page: "search", searchId: decodeURIComponent(id) } : { page: "home" };
}

export function useRoute(): Route {
  const [route, setRoute] = useState(() => parse(window.location.hash));

  useEffect(() => {
    const onChange = () => {
      setRoute(parse(window.location.hash));
      window.scrollTo(0, 0);
    };
    window.addEventListener("hashchange", onChange);
    return () => window.removeEventListener("hashchange", onChange);
  }, []);

  return route;
}
