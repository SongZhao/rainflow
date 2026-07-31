import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Rainflow",
    short_name: "Rainflow",
    description: "Modern finance. Clear insights.",
    start_url: "/dashboard",
    display: "standalone",
    background_color: "#071014",
    theme_color: "#071014",
    orientation: "portrait-primary",
    icons: [
      {
        src: "/icon.svg",
        sizes: "any",
        type: "image/svg+xml",
        purpose: "any maskable",
      },
    ],
  };
}
