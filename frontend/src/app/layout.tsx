import type { Metadata, Viewport } from "next";
import { Inter, Space_Grotesk } from "next/font/google";
import { Providers } from "@/components/providers";
import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
});

const spaceGrotesk = Space_Grotesk({
  subsets: ["latin"],
  variable: "--font-space-grotesk",
  display: "swap",
});

export const metadata: Metadata = {
  title: {
    default: "AstraLend — Cross-chain lending, one unified position",
    template: "%s · AstraLend",
  },
  description:
    "Supply liquidity, post collateral on any supported chain and borrow against it from another. AstraLend keeps one global position in sync over Chainlink CCIP.",
  openGraph: {
    title: "AstraLend",
    description: "Cross-chain lending with one unified position, synced over Chainlink CCIP.",
    type: "website",
  },
};

export const viewport: Viewport = {
  themeColor: "#05060c",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${inter.variable} ${spaceGrotesk.variable}`}>
      <body className="min-h-dvh antialiased">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
