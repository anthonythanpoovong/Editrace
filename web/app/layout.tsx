import type { ReactNode } from "react";

export const metadata = {
  title: "Editrace",
  description: "Placeholder app for the deploy pipeline (#48).",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
