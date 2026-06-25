import type { Metadata, Viewport } from "next";
import { Geist_Mono, Spectral, Schibsted_Grotesk } from "next/font/google";
import "./globals.css";

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

const spectral = Spectral({
  variable: "--font-spectral",
  subsets: ["latin"],
  weight: ["300", "400", "500"],
  style: ["normal", "italic"],
});

const schibstedGrotesk = Schibsted_Grotesk({
  variable: "--font-schibsted-grotesk",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
});

export const metadata: Metadata = {
  metadataBase: new URL('https://my-buisness.vercel.app'),
  title: "Hygge — Everything happening in St. Joseph.",
  description:
    "Everything happening in St. Joseph, in one calm place. Local events, a shared calendar, and a daily quest. Built for Saint Joseph, MN.",
  applicationName: "Hygge",
  appleWebApp: {
    capable: true,
    title: "Hygge",
    statusBarStyle: "default",
  },
};

export const viewport: Viewport = {
  themeColor: "#e1dbc9",
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${geistMono.variable} ${spectral.variable} ${schibstedGrotesk.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
