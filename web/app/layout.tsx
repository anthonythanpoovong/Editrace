import { JetBrains_Mono, Space_Grotesk } from "next/font/google";
import type { ReactNode } from "react";

export const metadata = {
  title: "Editrace",
  description: "Turn a video's editing style into a reusable template.",
};

// The coming-soon page's two typefaces (#149), self-hosted by Next at build time. They load as CSS variables so only
// pages that ask for them (landing.module.css) change; the login and account pages keep the browser default.
const sans = Space_Grotesk({ subsets: ["latin"], weight: ["400", "500", "600", "700"], variable: "--font-space-grotesk" });
const mono = JetBrains_Mono({ subsets: ["latin"], weight: ["400", "500", "700"], variable: "--font-jetbrains-mono" });

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className={`${sans.variable} ${mono.variable}`}>
      <body>{children}</body>
    </html>
  );
}
